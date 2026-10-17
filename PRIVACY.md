# Privacy

Syg sends anonymous usage statistics, so that what gets fixed and improved
follows how it is really used: which commands run, which rules fire, how large
modules get, where it is slow. This page says exactly what is sent, what never
is, and how to turn it off.

## What is sent

One event per command, with these fields and nothing else:

| Field | What it holds |
|---|---|
| `schema`, `version` | the event format, and Syg's version |
| `os`, `arch` | the operating system and CPU architecture |
| `ci` | the CI provider running Syg (`github`, `gitlab`, ...), or `none` |
| `command` | the command (`check`, `build`, ...), never its arguments |
| `exit`, `duration_ms` | the exit code, and how long the command took |
| `nodes`, `edges` | the size of the compiled module, in buckets (`11-50`) |
| `raw_ratio` | the share of objects written as `raw`, in buckets |
| `fired` | the codes of the rules that reported a finding, with counts (`CHK-PRB-005: 2`) |
| `disabled` | the codes of rules your `syg.yaml` turns off |
| `features` | which kinds of construct the module uses (`environments`, `profiles`, `relate`, ...) |
| `target`, `format` | the output layout and findings format chosen |
| `crash` | for an internal error, the names of Syg's own functions on its stack |
| `id` | a random identifier for your installation, created on first use; none in CI |
| `event_id`, `time` | a random identifier for the event, so a resend counts once, and when it happened |

`syg telemetry show` prints the queued events, exactly as they will be sent.

## What is never sent

Nothing from your module or your machine: no module, service, config, secret
or image names, no label values, no file names or paths, no finding text, no
hostname, user name or hardware identifier. The installation identifier is
random, not derived from anything about your machine. Your IP address reaches
the relay, as with any request. The relay neither stores nor forwards it;
Vercel, which runs the relay, keeps its request logs for an hour.

## Where it goes

Events go to Syg's relay at `api.syg.vishisht.tech`, which drops the IP
address and forwards them to an analytics project used only for Syg, at
PostHog in the EU. PostHog keeps them for 12 months and then deletes them.
The relay's code is public, in
[`relay/`](https://github.com/vishisht16/syg/tree/main/relay).

## When it is sent

- Never in a development build.
- Outside CI, never before the one-line notice has been shown on a terminal.
- In the background: a command adds its event to a queue in your config
  directory and, at most once an hour, starts `syg telemetry send`, a separate
  process that sends the queue and exits, giving up after two seconds. No
  command waits for it, and a failure is silent.
- In CI, which has no later run, at exit, waiting at most 250 ms.

## Turning it off

Any of these turns it off; nothing is sent, queued or checked:

- `syg telemetry off`, for your user;
- `SYG_TELEMETRY=off` in the environment, for one command or a CI job;
- `DO_NOT_TRACK=1`, the convention shared with other tools.

`syg telemetry status` says which is in effect.

## The update check

At most once a day, outside CI, `syg telemetry send` also asks the relay for
the latest release, sending Syg's version, OS and architecture. When a newer
one exists, a later command prints a one-line notice on a terminal. It is off
whenever telemetry is.
