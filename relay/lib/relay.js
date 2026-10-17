// Syg's relay, at api.syg.vishisht.tech.
//
//   POST /v1/events   a batch of usage events from the CLI. Each event is
//                     checked against the allowlist below (the fields the
//                     privacy page lists) and forwarded to PostHog with the
//                     sender's IP address dropped and geolocation off.
//                     Anything else is discarded.
//   GET  /v1/version  {"latest": "X.Y.Z"}, for the CLI's daily update check:
//                     the newest release of github.com/vishisht16/syg that is
//                     not a pre-release. It counts as an event too (version,
//                     OS and architecture only).
//
// Its one setting is POSTHOG_KEY, the PostHog project's API key. POSTHOG_HOST
// overrides the PostHog region.
//
// The CLI never depends on the relay: it sends in the background and gives up
// silently, so a relay that is down costs nothing but data.

const ENUMS = {
  command: ["build", "check", "docs", "explain", "fmt", "graph", "help", "init", "lsp", "mod", "other", "rules", "schema", "snapshot", "telemetry", "version", "why"],
  ci: ["azure", "bitbucket", "buildkite", "circleci", "codebuild", "drone", "github", "gitlab", "jenkins", "none", "other", "teamcity", "travis"],
  nodes: ["0", "1-10", "11-50", "51-200", "201-1000", "1001+"],
  edges: ["0", "1-10", "11-50", "51-200", "201-1000", "1001+"],
  raw_ratio: ["0", "1-10%", "11-25%", "26-50%", "51%+"],
  target: ["argo", "kustomize", "plain"],
  format: ["github", "json", "sarif", "text"],
  os: ["linux", "darwin", "windows", "freebsd"],
  arch: ["amd64", "arm64"],
};
const FEATURES = ["environments", "extern", "imports", "policy", "profiles", "raw", "relate", "snapshot", "baseline"];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const CODE = /^CHK-[A-Z0-9]+(-[A-Z0-9]+)*-\d{3}$/;
const VERSION = /^\d{1,4}\.\d{1,4}\.\d{1,4}(-[a-z0-9.]{1,20})?$/;
const FUNC = /^[A-Za-z0-9_./()*-]{1,120}$/;
const MAX_BATCH = 200;

const POSTHOG_HOST = "https://eu.i.posthog.com";
const RELEASES = "https://github.com/vishisht16/syg/releases";
const HOUR = 60 * 60 * 1000;

// clean returns the event reduced to allowed fields and values, or null.
export function clean(e) {
  if (typeof e !== "object" || e === null || e.schema !== 1) return null;
  if (!UUID.test(e.event_id || "") || !VERSION.test(e.version || "")) return null;
  const out = { schema: 1, event_id: e.event_id, version: e.version };
  if (e.id !== undefined) {
    if (!UUID.test(e.id)) return null;
    out.id = e.id;
  }
  for (const [k, allowed] of Object.entries(ENUMS)) {
    if (e[k] === undefined) continue;
    if (!allowed.includes(e[k])) return null;
    out[k] = e[k];
  }
  if (!out.command || !out.os || !out.arch || !out.ci) return null;
  for (const k of ["exit", "duration_ms", "time"]) {
    if (e[k] === undefined) continue;
    if (!Number.isInteger(e[k]) || e[k] < 0 || e[k] > 4102444800) return null;
    out[k] = e[k];
  }
  if (e.fired !== undefined) {
    if (typeof e.fired !== "object" || e.fired === null) return null;
    out.fired = {};
    for (const [code, n] of Object.entries(e.fired)) {
      if (!CODE.test(code) || !Number.isInteger(n) || n < 0 || n > 100000) return null;
      out.fired[code] = n;
    }
  }
  if (e.disabled !== undefined) {
    if (!Array.isArray(e.disabled) || !e.disabled.every((c) => CODE.test(c))) return null;
    out.disabled = e.disabled.slice(0, 100);
  }
  if (e.features !== undefined) {
    if (!Array.isArray(e.features) || !e.features.every((f) => FEATURES.includes(f))) return null;
    out.features = e.features;
  }
  if (e.crash !== undefined) {
    if (!Array.isArray(e.crash) || !e.crash.every((f) => FUNC.test(f))) return null;
    out.crash = e.crash.slice(0, 12);
  }
  return out;
}

// toPostHog shapes a clean event for PostHog's batch API. The distinct ID is
// the installation's random ID, or, in CI, the event's own: CI runs are not
// people, and are not joined up.
export function toPostHog(e) {
  const { event_id, id, time, ...props } = e;
  return {
    event: "syg_" + e.command,
    uuid: event_id,
    distinct_id: id || "ci-" + event_id,
    timestamp: time ? new Date(time * 1000).toISOString() : undefined,
    properties: { ...props, $ip: null, $geoip_disable: true, $process_person_profile: Boolean(id) },
  };
}

// forward sends clean events to PostHog. It never rejects: a failure only
// loses the batch.
function forward(env, list, get) {
  if (!env.POSTHOG_KEY || list.length === 0) return Promise.resolve();
  return get((env.POSTHOG_HOST || POSTHOG_HOST) + "/batch/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ api_key: env.POSTHOG_KEY, batch: list.map(toPostHog) }),
  }).then(
    () => {},
    () => {},
  );
}

const known = { version: null, at: -Infinity };

// latest is the newest release that is not a pre-release: where GitHub's
// latest-release page redirects to, remembered for an hour. When GitHub
// cannot be reached, the last answer stands and the next call asks again.
export async function latest({ get = fetch, now = Date.now(), memo = known } = {}) {
  if (now - memo.at < HOUR) return memo.version;
  try {
    const r = await get(RELEASES + "/latest", { method: "HEAD", redirect: "manual", signal: AbortSignal.timeout(1500) });
    const m = /\/releases\/tag\/v(\d{1,4}\.\d{1,4}\.\d{1,4})$/.exec(r.headers.get("location") || "");
    memo.version = m ? m[1] : null;
    memo.at = now;
  } catch {
    // keep the last answer
  }
  return memo.version;
}

// events answers POST /v1/events.
export async function events(req, { env = process.env, waitUntil, get = fetch } = {}) {
  let body;
  try {
    body = await req.json();
  } catch {
    return new Response(null, { status: 400 });
  }
  const list = (Array.isArray(body?.events) ? body.events : []).slice(0, MAX_BATCH).map(clean).filter(Boolean);
  waitUntil(forward(env, list, get));
  return new Response(null, { status: 202 });
}

// version answers GET /v1/version.
export async function version(req, { env = process.env, waitUntil, get = fetch, memo = known } = {}) {
  const q = new URL(req.url).searchParams;
  const v = q.get("v") || "";
  const ping = clean({
    schema: 1, event_id: crypto.randomUUID(), version: VERSION.test(v) ? v : "0.0.0",
    command: "version", ci: "none", os: q.get("os"), arch: q.get("arch"),
  });
  if (ping) waitUntil(forward(env, [ping], get));
  const newest = await latest({ get, memo });
  return Response.json(newest ? { latest: newest } : {}, { headers: { "Cache-Control": "no-store" } });
}
