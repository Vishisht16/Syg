#!/usr/bin/env python3
"""Renders a package manager's manifest for a release, from SHA256SUMS.

    python3 hack/render.py brew  VERSION SHA256SUMS > Formula/syg.rb
    python3 hack/render.py scoop VERSION SHA256SUMS > bucket/syg.json
"""
import json
import sys

kind, version, sums_path = sys.argv[1], sys.argv[2], sys.argv[3]
sums = {}
for line in open(sums_path):
    digest, name = line.split()
    sums[name.lstrip("*")] = digest
base = f"https://github.com/vishisht16/syg/releases/download/v{version}"


def asset(os_, arch):
    ext = "zip" if os_ == "windows" else "tar.gz"
    name = f"syg_{version}_{os_}_{arch}.{ext}"
    if name not in sums:
        sys.exit(f"render: {name} is not in {sums_path}")
    return f"{base}/{name}", sums[name]


if kind == "brew":
    t = open("templates/homebrew-tap/Formula/syg.rb").read()
    for os_ in ("darwin", "linux"):
        for arch in ("amd64", "arm64"):
            url, digest = asset(os_, arch)
            t = t.replace(f"@{os_}_{arch}_url@", url).replace(f"@{os_}_{arch}_sha256@", digest)
    print(t.replace("@version@", version), end="")
elif kind == "scoop":
    m = {
        "version": version,
        "description": "A typed language for a Kubernetes service's deployment surface, and the compiler that checks it",
        "homepage": "https://syg.vishisht.tech",
        "license": {"identifier": "Proprietary", "url": "https://syg.vishisht.tech/eula"},
        "architecture": {},
        "bin": "syg.exe",
        "checkver": {"github": "https://github.com/vishisht16/syg"},
        "autoupdate": {"architecture": {}},
    }
    for arch, key in (("amd64", "64bit"), ("arm64", "arm64")):
        url, digest = asset("windows", arch)
        m["architecture"][key] = {"url": url, "hash": digest}
        m["autoupdate"]["architecture"][key] = {
            "url": f"https://github.com/vishisht16/syg/releases/download/v$version/syg_$version_windows_{arch}.zip"}
    print(json.dumps(m, indent=4))
else:
    sys.exit(f"render: unknown kind {kind}")
