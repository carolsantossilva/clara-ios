#!/usr/bin/env bash
# Falha se o log do xcodebuild tiver avisos do compilador no código do projeto.
#
# Substitui SWIFT_TREAT_WARNINGS_AS_ERRORS na linha de comando: essa opção vale
# para todos os targets, inclusive dependências remotas, que o Xcode compila com
# -suppress-warnings (as duas opções juntas são erro). Aqui só o nosso código conta.
# Uso: no_warnings.sh <log-do-xcodebuild>
set -euo pipefail

log=$1
root=${GITHUB_WORKSPACE:-$(pwd)}
pattern="^${root}/(App|AppUITests|Packages/ClaraKit/(Sources|Tests))/[^:]+:[0-9]+:[0-9]+: warning: "

warnings=$(grep -E "$pattern" "$log" | sort -u || true)
if [[ -z "$warnings" ]]; then
  echo "Nenhum aviso do compilador no código do projeto."
  exit 0
fi

while IFS= read -r line; do
  file=${line%%:*}
  rest=${line#*:}
  lineno=${rest%%:*}
  message=${line#*warning: }
  echo "::error file=${file#"$root"/},line=${lineno}::${message}"
done <<< "$warnings"
echo "$(wc -l <<< "$warnings" | tr -d ' ') aviso(s) do compilador. Código gerado por IA não entra com warning."
exit 1
