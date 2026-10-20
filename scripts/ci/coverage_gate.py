#!/usr/bin/env python3
"""Falha se a cobertura de linhas dos módulos ficar abaixo do mínimo.

Uso: coverage_gate.py <Resultado.xcresult>
Lê o mínimo, os targets e os arquivos ignorados de guardrails/thresholds.json.
"""
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
config = json.loads((ROOT / "guardrails/thresholds.json").read_text())
minimum = config["min_line_coverage"]
excluded = set(config.get("coverage_excluded_targets", []))
excluded_files = set(config.get("coverage_excluded_files", []))

report = json.loads(subprocess.run(
    ["xcrun", "xccov", "view", "--report", "--json", sys.argv[1]],
    check=True, capture_output=True, text=True,
).stdout)

covered = executable = 0
rows = []
for target in report.get("targets", []):
    name = target["name"].removesuffix(".framework").removesuffix(".app").removesuffix(".o")
    if name.endswith(("Tests", "UITests")) or name in excluded:
        continue
    files = [f for f in target.get("files", []) if f["name"] not in excluded_files]
    target_covered = sum(f["coveredLines"] for f in files)
    target_executable = sum(f["executableLines"] for f in files)
    covered += target_covered
    executable += target_executable
    rows.append((name, target_covered / target_executable if target_executable else 0.0))

if excluded_files:
    print(f"Arquivos fora do cálculo: {', '.join(sorted(excluded_files))}")
for name, value in sorted(rows):
    print(f"  {name:<28} {value:6.1%}")
if executable == 0:
    sys.exit("Nenhuma linha de código coberta encontrada no relatório.")
total = covered / executable
print(f"Cobertura total: {total:.1%} (mínimo {minimum:.0%})")
if total < minimum:
    print(f"::error::Cobertura {total:.1%} abaixo do mínimo de {minimum:.0%}. Escreva testes; não baixe o limite.")
    sys.exit(1)
