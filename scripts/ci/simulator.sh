#!/usr/bin/env bash
# Prints the UDID of an available iPhone on the newest installed iOS runtime.
set -euo pipefail
xcrun simctl list devices available --json | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    return [int(n) for n in re.findall(r"\d+", runtime.rsplit("iOS", 1)[-1])]
for runtime in sorted((r for r in devices if ".iOS-" in r), key=version, reverse=True):
    phones = [d for d in devices[runtime] if d["name"].startswith("iPhone")]
    if phones:
        print(phones[0]["udid"])
        sys.exit(0)
sys.exit("No iPhone simulator available")
'
