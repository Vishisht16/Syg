// node --test relay/relay.test.js
import { test } from "node:test";
import assert from "node:assert/strict";
import { clean, toPostHog, latest, events, version } from "./lib/relay.js";

const good = {
  schema: 1, event_id: "824cb2e9-9eb8-4c15-b4c6-d8e4eb28d388", id: "11111111-2222-4333-8444-555555555555",
  time: 1792182677, version: "1.0.0-rc.9", os: "linux", arch: "amd64", ci: "none", command: "check",
  exit: 0, duration_ms: 3, nodes: "1-10", edges: "1-10", raw_ratio: "0",
  fired: { "CHK-PDB-004": 1, "CHK-T2-CAP-001": 2 }, features: ["environments", "imports"], format: "text",
};

// github answers HEAD /releases/latest the way GitHub does: a redirect to the
// release's tag, or to the release list when there is none.
function github(location, calls = []) {
  return async (url, init) => {
    calls.push(url);
    return new Response(null, { status: 302, headers: location ? { location } : {} });
  };
}

test("a well-formed event passes, field for field", () => {
  assert.deepEqual(clean(good), good);
});

test("anything outside the allowlist rejects the event", () => {
  for (const bad of [
    { ...good, command: "rm -rf /" },
    { ...good, fired: { "payments-api": 1 } },
    { ...good, features: ["secret-sauce"] },
    { ...good, id: "my-laptop" },
    { ...good, version: "1.0.0; drop table" },
    { ...good, crash: ["main.go:12 user said hello world"] },
    { ...good, exit: -1 },
  ]) {
    assert.equal(clean(bad), null, JSON.stringify(bad));
  }
  assert.ok(!("module" in clean({ ...good, module: "payments" })), "an unknown field is dropped");
});

test("a crash's frames pass as Go names them, generics and closures included", () => {
  const crash = ["internal/env.find[...]", "internal/cli.Main.func2", "internal/lsp.(*server).handle"];
  assert.deepEqual(clean({ ...good, crash }).crash, crash);
});

test("PostHog gets no IP address, and no person for a CI run", () => {
  const ci = toPostHog(clean({ ...good, id: undefined, ci: "github" }));
  assert.equal(ci.properties.$ip, null);
  assert.equal(ci.properties.$geoip_disable, true);
  assert.equal(ci.properties.$process_person_profile, false);
  assert.equal(ci.distinct_id, "anon-" + good.event_id);
  const local = toPostHog(clean(good));
  assert.equal(local.distinct_id, good.id);
  assert.equal(local.uuid, good.event_id);
});

test("events: only clean events reach PostHog, in the background", async () => {
  const sent = [];
  const get = async (url, init) => {
    sent.push({ url, body: JSON.parse(init.body), signal: init.signal });
    return new Response(null);
  };
  const waits = [];
  const req = new Request("https://api.syg.vishisht.tech/v1/events", {
    method: "POST", body: JSON.stringify({ events: [good, { schema: 1 }] }),
  });
  const r = await events(req, { env: { POSTHOG_KEY: "phc_test" }, waitUntil: (p) => waits.push(p), get });
  assert.equal(r.status, 202);
  await Promise.all(waits);
  assert.equal(sent.length, 1);
  assert.equal(sent[0].url, "https://eu.i.posthog.com/batch/");
  assert.equal(sent[0].body.api_key, "phc_test");
  assert.equal(sent[0].body.batch.length, 1, "the malformed event was dropped");
  assert.equal(sent[0].body.batch[0].event, "syg_check");
  assert.ok(sent[0].signal instanceof AbortSignal, "the request to PostHog has a time limit");

  const bad = new Request("https://api.syg.vishisht.tech/v1/events", { method: "POST", body: "not json" });
  assert.equal((await events(bad, { env: {}, waitUntil: () => {}, get })).status, 400);
});

test("events: a PostHog failure is silent", async () => {
  const waits = [];
  const req = new Request("https://api.syg.vishisht.tech/v1/events", { method: "POST", body: JSON.stringify({ events: [good] }) });
  const r = await events(req, {
    env: { POSTHOG_KEY: "phc_test" }, waitUntil: (p) => waits.push(p),
    get: async () => { throw new Error("unreachable"); },
  });
  assert.equal(r.status, 202);
  await Promise.all(waits); // resolves: a lost batch is not an error
});

test("version: the latest release, and the check counted as an event of its own", async () => {
  const sent = [];
  const get = async (url, init) => {
    if (url.startsWith("https://github.com/")) return github("https://github.com/Vishisht16/Syg/releases/tag/v1.0.1")(url, init);
    sent.push(JSON.parse(init.body));
    return new Response(null);
  };
  const waits = [];
  const req = new Request("https://api.syg.vishisht.tech/v1/version?v=1.0.0&os=darwin&arch=arm64");
  const r = await version(req, { env: { POSTHOG_KEY: "phc_test" }, waitUntil: (p) => waits.push(p), get, memo: { version: null, at: -Infinity } });
  assert.deepEqual(await r.json(), { latest: "1.0.1" });
  assert.equal(r.headers.get("cache-control"), "no-store");
  await Promise.all(waits);
  assert.equal(sent.length, 1);
  const check = sent[0].batch[0];
  assert.equal(check.event, "syg_update_check", "not syg_version, which is someone running `syg version`");
  assert.equal(check.properties.os, "darwin");
  assert.match(check.distinct_id, /^anon-/);
  assert.equal(check.properties.$process_person_profile, false);
});

test("latest: no release, a pre-release, or GitHub unreachable", async () => {
  const fresh = () => ({ version: null, at: -Infinity });
  assert.equal(await latest({ get: github("https://github.com/vishisht16/syg/releases"), memo: fresh() }), null);
  assert.equal(await latest({ get: github("https://github.com/vishisht16/syg/releases/tag/v1.1.0-rc.1"), memo: fresh() }), null);

  const memo = { version: "1.0.0", at: 0 };
  const down = async () => { throw new Error("unreachable"); };
  assert.equal(await latest({ get: down, now: 2 * 60 * 60 * 1000, memo }), "1.0.0", "the last answer stands");
  assert.equal(memo.at, 0, "and the next call asks again");
});

test("latest: asked at most once an hour", async () => {
  const calls = [];
  const memo = { version: null, at: -Infinity };
  const get = github("https://github.com/vishisht16/syg/releases/tag/v1.2.3", calls);
  assert.equal(await latest({ get, now: 0, memo }), "1.2.3");
  assert.equal(await latest({ get, now: 59 * 60 * 1000, memo }), "1.2.3");
  assert.equal(calls.length, 1);
  await latest({ get, now: 61 * 60 * 1000, memo });
  assert.equal(calls.length, 2);
});
