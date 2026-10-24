# How Syg was tested

Syg's job is to stop mistakes before they reach a cluster, so before 1.0 it
went through a trial by fire: six rounds of testing by an independent
auditor whose only brief was to break it, then the same attacks on Windows
and macOS, on their own machines. It broke, more than once. This page says
what it went through, what broke and what changed, what held, and what has
not been tested yet.

## What it went through

- 255 scripted attacks in the first round alone, across ten areas, from the
  syntax to the editor's language server.
- About 1.5 million fuzz runs on Syg's five fuzzers, and seven new fuzz
  targets written for the parts nothing had fuzzed yet.
- Inputs far past anything real: 100 MB strings, 724 MB of source, a module
  of 200,000 services, nearly 900,000 declarations, and nesting a million
  levels deep.
- Memory limits down to 64 MiB, builds racing each other, builds stopped
  halfway, and a full disk.
- Hostile file names, symbolic links and directory junctions, pipes in place
  of files, YAML bombs, and malformed editor traffic.
- Every release binary compared with the others, and the arm64 one run under
  emulation; then Windows and macOS on their own machines, on Intel and on
  ARM: five platforms in all.

Alongside it, every change runs the tests on Linux, macOS and Windows, with
the race detector; the fuzzers; static analysis and a scan for known
vulnerabilities, of Syg and of the Go toolchain it is built with; and kind
clusters on three Kubernetes versions, where what Syg emits is applied,
synced with Argo CD, and its network policies enforced.

## What broke, and what changed

The testing recorded 72 findings, 4 of them high. Every high and medium
finding was fixed and tested again before 1.0.0-rc.4, and the rest were
fixed, or recorded as decisions with their reasons. These taught us the
most:

- **Output that outgrew its input.** A 30 KB file of malformed input made
  Syg print over a gigabyte of errors in about a second: each error printed
  its whole line again. Now a line is cut to a window around the error, and
  repeated errors are dropped. The same file prints under 2 KB.
- **Input without a ceiling.** An 80 MB string, a language-server message
  claiming a 100 GB body, or a module of 100,000 services could exhaust
  memory. Now files, modules, messages and the work a build does each have a
  limit, and past it Syg refuses, with exit code 2, instead of running out.
  `syg explain limit` lists them.
- **Links out of the repository.** A symbolic link, and on Windows a
  directory junction, inside a repository could lead Syg to read files
  outside it, and to write through it. Now a link that leads out of the
  repository is refused before anything is read or written, on every
  platform.
- **A schema choosing where to write.** `syg schema vendor` named its files
  after a CRD's group and kind, so a hostile CRD could aim the write outside
  the module. Now those names are checked as the API server checks them, and
  every write stays inside.
- **Pods the security rules did not see.** A privileged pod template inside
  a custom resource, or behind a decoy, was not judged by the rules that look
  for privileged pods. Now Syg finds every pod spec by its shape, at any
  depth, and says so when it cannot read one.
- **File names that write to your logs.** A file name holding a newline
  could forge an annotation in a GitHub Actions log, and escape characters
  could rewrite a terminal. Now every name Syg prints is made printable
  first.
- **One file for two names.** On macOS and Windows, two objects whose names
  differed only in case became one file, and an import spelled in another
  case worked there and failed on Linux. Now both are errors, on every
  platform.

## What held

- No crash, hang or panic in any fuzz run.
- No data race, under the race detector, in any test or probe.
- The same output, byte for byte, across platforms, processor counts, time
  zones and runs.
- YAML bombs refused at flat memory.
- An input Syg could not use refused with a message in its own words, and
  the documented exit code: never a crash.

## What has not been tested yet

- Memory beyond 16 GB, and the largest modules the limits allow.
- Runs of many hours.
- Fetching schemas through expired or wrong certificates, slow servers and
  dropped connections.
- Hardened containers: read-only file systems, strict seccomp profiles and
  process limits.
- Files owned by root or by another user.
- Machines with many cores.
- Files OneDrive keeps in the cloud, and macOS's quarantine on a downloaded
  binary.
- Admission on a live cluster with Pod Security enforced. The clusters
  above apply what Syg emits, but not under every admission policy.

## Help us break it

Syg is breakable, and we would rather hear it from you than from production.
Test it as hard as you like under the
[security policy](security.md#test-it-yourself): it authorizes good-faith
research, says what is out of bounds, and asks you to report privately and
to give us time to fix a problem before you make it public. We acknowledge
a report within 3 business days, and credit its reporter in the advisory and
in the [hall of fame](security.md#hall-of-fame), if they wish.

## Join the testing group

If you would like to test what comes next before it is released, such as
release candidates, new rules and new platforms, write to
syg@vishisht.tech. Tell us what you would like to test, and on what.
