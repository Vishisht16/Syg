#!/usr/bin/env python3
"""Reads `go test -json` on stdin and prints only each package's result.

The public release workflow runs the private source's tests in a public log.
A failing test's output (a diff, a stack trace, a compiler error) can quote
source, so none of it is printed, nor even the packages' names, which would
describe the source's structure: only how many packages passed and failed.
A failure is investigated in the private repository's CI, which runs the same
tests with full output.

    go test -json ./... 2>/dev/null | python3 hack/quiet-test.py
"""
import json
import sys

results = {}
for line in sys.stdin:
    try:
        ev = json.loads(line)
    except ValueError:
        continue  # a non-JSON line is never echoed
    if ev.get("Test"):
        continue  # per-test events: only the package's verdict is reported
    action, pkg = ev.get("Action"), ev.get("Package", "")
    if action in ("pass", "fail", "skip") and pkg:
        results[pkg] = action
    elif action == "build-fail":
        results[ev.get("ImportPath", pkg) or "build"] = "fail"

failed = sum(1 for a in results.values() if a == "fail")
passed = sum(1 for a in results.values() if a == "pass")
print(f"tests: {passed} packages passed, {failed} failed, {len(results) - passed - failed} without tests")
sys.exit(1 if failed or not results else 0)
