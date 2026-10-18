#!/usr/bin/env bash
# Imprime o UDID de um iPhone disponível no runtime iOS mais novo instalado.
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
sys.exit("Nenhum simulador de iPhone disponível")
'
