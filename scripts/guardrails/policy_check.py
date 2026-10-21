#!/usr/bin/env python3
"""Verificações de política para código gerado por IA (e por pessoas).

Roda no CI (job "policy") e localmente (hook de Stop do Claude Code).

Regras:
  1. Dependências: toda dependência externa precisa estar em
     guardrails/allowed-dependencies.txt, e pacotes Swift remotos precisam de
     versão exata (`exact:` ou `revision:`). Sem exceção por label.
  2. Guardrails: mudar um caminho de guardrails/protected-paths.txt exige o
     label "guardrails-change".
  3. Supressões: adicionar um padrão de guardrails/suppression-patterns.txt
     exige o label "guardrail-exception".
  4. Testes: diminuir o número de testes exige o label "guardrail-exception".

Uso:
  policy_check.py --mode pr --base <sha>     # PR: regras 1 a 4
  policy_check.py --mode push --base <sha>   # push na main: só a regra 1
  policy_check.py --mode local               # árvore de trabalho contra origin/main (ou HEAD)
  policy_check.py --mode staged              # só o que está no commit (hook de pre-commit)

Labels do PR vêm da variável PR_LABELS (JSON com a lista de nomes).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EMPTY_TREE = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
LABEL_GUARDRAILS = "guardrails-change"
LABEL_EXCEPTION = "guardrail-exception"
IN_CI = os.environ.get("GITHUB_ACTIONS") == "true"


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    notices: list[str] = field(default_factory=list)

    def error(self, message: str, file: str | None = None, line: int | None = None) -> None:
        self.errors.append(message)
        annotate("error", message, file, line)

    def notice(self, message: str, file: str | None = None, line: int | None = None) -> None:
        self.notices.append(message)
        annotate("warning", message, file, line)


def annotate(level: str, message: str, file: str | None, line: int | None) -> None:
    if not IN_CI:
        return
    location = ""
    if file:
        location = f" file={file}" + (f",line={line}" if line else "")
    print(f"::{level}{location}::{message}")


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout


def ref_exists(ref: str) -> bool:
    return subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
        cwd=ROOT, capture_output=True,
    ).returncode == 0


def read_list(path: str, staged: bool = False) -> list[str]:
    text = git("show", f":{path}") if staged else (ROOT / path).read_text(encoding="utf-8")
    lines = text.splitlines()
    return [line for line in lines if line.strip() and not line.lstrip().startswith("#")]


# ---------------------------------------------------------------- diff


@dataclass
class Diff:
    touched: list[str]
    added_lines: list[tuple[str, int, str]]  # (arquivo, linha, conteúdo)
    sources: dict[str, str] = field(default_factory=dict)


def collect_diff(base: str, local: bool, staged: bool = False) -> Diff:
    # PR/push: base...HEAD. Local: base com a árvore de trabalho. Staged: base com o índice.
    if staged:
        spec = ["--cached", base]
    elif local:
        spec = [base]
    elif base == EMPTY_TREE:
        spec = [EMPTY_TREE, "HEAD"]
    else:
        spec = [f"{base}...HEAD"]

    status = git("diff", "--name-status", "--no-renames", *spec)
    touched = []
    for row in status.splitlines():
        _, _, path = row.partition("\t")
        touched.append(path)

    added: list[tuple[str, int, str]] = []
    current, line_no = None, 0
    in_hunk = False
    for row in git("diff", "-U0", "--no-renames", *spec).splitlines():
        if row.startswith("diff --git "):
            current, in_hunk = None, False
        elif not in_hunk and row.startswith("+++ "):
            current = row[6:] if row.startswith("+++ b/") else None
        elif row.startswith("@@"):
            in_hunk = True
            match = re.search(r"\+(\d+)", row)
            line_no = int(match.group(1)) if match else 0
        elif row.startswith("+") and current:
            added.append((current, line_no, row[1:]))
            line_no += 1

    if local and not staged:
        for path in git("ls-files", "--others", "--exclude-standard").splitlines():
            touched.append(path)
            try:
                text = (ROOT / path).read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            added += [(path, i, line) for i, line in enumerate(text.splitlines(), 1)]

    sources = {}
    for path in {path for path, _, _ in added if path.endswith((".swift", ".m", ".h"))}:
        try:
            if staged:
                sources[path] = git("show", f":{path}")
            elif local:
                sources[path] = (ROOT / path).read_text(encoding="utf-8")
            else:
                sources[path] = git("show", f"HEAD:{path}")
        except (UnicodeDecodeError, OSError, subprocess.CalledProcessError):
            continue

    return Diff(touched=touched, added_lines=added, sources=sources)


# ---------------------------------------------------------------- regra 1


SWIFT_LITERAL = r'"[^"\\\r\n]+"'
SWIFT_PACKAGE_CALL = re.compile(r"\.\s*package\s*\(")
SWIFT_DECLARATION = re.compile(
    r"\.\s*package\s*\(\s*(?:name\s*:\s*" + SWIFT_LITERAL + r"\s*,\s*)?"
    r"(?:path\s*:\s*" + SWIFT_LITERAL + r"|url\s*:\s*"
    r'"(?P<url>[^"\\\r\n]+)"\s*,\s*(?:exact|revision)\s*:\s*' + SWIFT_LITERAL + r")\s*\)"
)


def block_comment_end(text: str, start: int) -> int:
    position, depth = start + 2, 1
    while position < len(text) and depth:
        if text.startswith("/*", position):
            depth += 1
            position += 2
        elif text.startswith("*/", position):
            depth -= 1
            position += 2
        else:
            position += 1
    return position


def string_token(text: str, start: int, swift: bool = True) -> tuple[int, list[tuple[int, int]]] | None:
    """Return a string end and any executable Swift interpolation ranges."""
    position, hashes = start, 0
    if text[position] == "#":
        while position < len(text) and text[position] == "#":
            hashes += 1
            position += 1
        if position == len(text) or text[position] != '"':
            return None
    elif text[position] not in ('"', "'"):
        return None

    quote = text[position]
    marker = '"""' if quote == '"' and text.startswith('"""', position) else quote
    closing = marker + "#" * hashes
    position += len(marker)
    interpolations = []
    while position < len(text):
        interpolation = "\\" + "#" * hashes + "(" if swift and quote == '"' else ""
        if interpolation and text.startswith(interpolation, position):
            content_start = position + len(interpolation)
            end = interpolation_end(text, content_start)
            if end is not None:
                interpolations.append((content_start, end - 1))
                position = end
            else:
                position = content_start
        elif hashes and text.startswith("\\" + "#" * hashes, position):
            position += hashes + 2
        elif not hashes and text[position] == "\\":
            position += 2
        elif text.startswith(closing, position):
            return position + len(closing), interpolations
        else:
            position += 1
    return len(text), interpolations


def regex_token(text: str, start: int) -> tuple[int, list[tuple[int, int]]] | None:
    """Return a raw Swift regex end and any executable interpolation ranges."""
    if text[start] != "#":
        return None
    position = start
    while position < len(text) and text[position] == "#":
        position += 1
    hashes = position - start
    if position == len(text) or text[position] != "/":
        return None

    position += 1
    closing = "/" + "#" * hashes
    interpolation = "\\" + "#" * hashes + "("
    interpolations = []
    while position < len(text):
        if text.startswith(interpolation, position):
            content_start = position + len(interpolation)
            end = interpolation_end(text, content_start)
            if end is not None:
                interpolations.append((content_start, end - 1))
                position = end
            else:
                position = content_start
        elif text[position] == "\\":
            position += 2
        elif text.startswith(closing, position):
            return position + len(closing), interpolations
        else:
            position += 1
    return len(text), interpolations


def interpolation_end(text: str, start: int) -> int | None:
    position, depth = start, 1
    while position < len(text):
        if text.startswith("//", position):
            end = text.find("\n", position)
            position = len(text) if end < 0 else end
        elif text.startswith("/*", position):
            position = block_comment_end(text, position)
        else:
            token = regex_token(text, position) or string_token(text, position)
            if token:
                position = token[0]
            elif text[position] == "(":
                depth += 1
                position += 1
            elif text[position] == ")":
                depth -= 1
                position += 1
                if not depth:
                    return position
            else:
                position += 1
    return None


def blank(text: str) -> list[str]:
    return ["\n" if char == "\n" else " " for char in text]


def source_views(text: str, swift: bool = True) -> tuple[str, str, str]:
    """Return manifest text, executable code, and comments with offsets preserved."""
    manifest, code = list(text), list(text)
    comments = ["\n" if char == "\n" else " " for char in text]
    position = 0
    while position < len(text):
        if text.startswith("//", position):
            end = text.find("\n", position)
            end = len(text) if end < 0 else end
            comments[position:end] = text[position:end]
            code[position:end] = ["\n" if char == "\n" else " " for char in text[position:end]]
            manifest[position:end] = code[position:end]
            position = end
        elif text.startswith("/*", position):
            start = position
            position = block_comment_end(text, position)
            comments[start:position] = text[start:position]
            masked = blank(text[start:position])
            code[start:position] = masked
            manifest[start:position] = masked
        else:
            token = (regex_token(text, position) if swift else None) or string_token(text, position, swift)
            if token is None:
                position += 1
            else:
                end, interpolations = token
                code[position:end] = blank(text[position:end])
                for start, stop in interpolations:
                    _, inner_code, inner_comments = source_views(text[start:stop], swift)
                    code[start:stop] = list(inner_code)
                    comments[start:stop] = list(inner_comments)
                position = end
    return "".join(manifest), "".join(code), "".join(comments)


GEM_CALL = re.compile(r"^[ \t]*gem\b", re.MULTILINE)
GEM = re.compile(r"^[ \t]*gem[ \t]+(['\"])(?P<name>[^'\"]+)\1(?P<options>[^\n]*)$", re.MULTILINE)
GEM_SOURCE_CALL = re.compile(r"^[ \t]*source\b", re.MULTILINE)
GEM_SOURCE = re.compile(r"^[ \t]*source[ \t]+(['\"])(?P<url>[^'\"]+)\1[^\n]*$", re.MULTILINE)
GEM_IMPORT = re.compile(r"^[ \t]*(?:gemspec|eval_gemfile)\b", re.MULTILINE)
GEM_SOURCE_OVERRIDE = re.compile(r":?(?:git|github|path|source|branch|ref|tag)\s*(?::|=>)")


def check_dependencies(report: Report, staged: bool = False) -> None:
    allowed = {tuple(line.split(None, 1)) for line in read_list("guardrails/allowed-dependencies.txt", staged)}
    tracked = git("ls-files", "--cached", *([] if staged else ["--others", "--exclude-standard"])).splitlines()

    for path in tracked:
        name = Path(path).name
        if name not in ("Package.swift", "Gemfile"):
            continue
        text = git("show", f":{path}") if staged else (ROOT / path).read_text(encoding="utf-8")
        if name == "Package.swift":
            manifest, code, _ = source_views(text)
            for match in SWIFT_PACKAGE_CALL.finditer(code):
                line = text.count("\n", 0, match.start()) + 1
                declaration = SWIFT_DECLARATION.match(manifest, match.start())
                if not declaration:
                    report.error(
                        "Declaração Swift não reconhecida: use `.package(path: \"...\")` "
                        "ou URL literal com versão literal `exact:`/`revision:`.", path, line,
                    )
                    continue
                if not declaration.group("url"):
                    continue
                url = declaration.group("url").removesuffix(".git")
                if ("swift", url) not in allowed:
                    report.error(
                        f"Dependência Swift fora da lista permitida: {url}. "
                        "Confira se o pacote existe e é o correto, depois peça para uma pessoa "
                        "adicioná-lo em guardrails/allowed-dependencies.txt.",
                        path, line,
                    )
        else:
            for call in GEM_SOURCE_CALL.finditer(text):
                source = GEM_SOURCE.match(text, call.start())
                line = text.count("\n", 0, call.start()) + 1
                if not source:
                    report.error("Origem Ruby não reconhecida; use https://rubygems.org.", path, line)
                elif source.group("url") != "https://rubygems.org":
                    report.error(f"Origem Ruby não permitida: {source.group('url')}.", path, line)

            for match in GEM_IMPORT.finditer(text):
                line = text.count("\n", 0, match.start()) + 1
                report.error("`gemspec` e `eval_gemfile` não são aceitos; declare gems diretamente no Gemfile.", path, line)

            for call in GEM_CALL.finditer(text):
                match = GEM.match(text, call.start())
                line = text.count("\n", 0, call.start()) + 1
                if not match:
                    report.error("Declaração Ruby não reconhecida; declare o nome literal da gem.", path, line)
                    continue
                name, options = match.group("name"), match.group("options")
                if GEM_SOURCE_OVERRIDE.search(options) or options.rstrip().endswith(","):
                    report.error(f"Origem ou continuação não permitida para a gem {name}.", path, line)
                if ("gem", name) not in allowed:
                    report.error(f"Gem fora da lista permitida: {name}.", path, line)


# ---------------------------------------------------------------- regra 2


def is_protected(path: str, prefixes: list[str]) -> bool:
    return any(path == p or (p.endswith("/") and path.startswith(p)) for p in prefixes)


def check_protected(report: Report, diff: Diff, labels: set[str] | None) -> None:
    prefixes = [line.strip() for line in read_list("guardrails/protected-paths.txt")]
    touched = sorted(p for p in diff.touched if is_protected(p, prefixes))
    if not touched:
        return
    listing = ", ".join(touched)
    if labels is None:
        report.notice(f"Arquivos de guardrail alterados (o PR vai precisar do label {LABEL_GUARDRAILS}): {listing}")
    elif LABEL_GUARDRAILS not in labels:
        report.error(
            f"Este PR altera arquivos de guardrail ({listing}). "
            f"Uma pessoa precisa revisar e adicionar o label '{LABEL_GUARDRAILS}'."
        )


# ---------------------------------------------------------------- regra 3


def check_suppressions(report: Report, diff: Diff, labels: set[str] | None) -> None:
    patterns = []
    for line in read_list("guardrails/suppression-patterns.txt"):
        regex, _, why = line.partition("\t")
        patterns.append((re.compile(regex), why.strip()))

    prefixes = [line.strip() for line in read_list("guardrails/protected-paths.txt")]
    views = {}
    hits = []
    for path, line_no, text in diff.added_lines:
        if not path.endswith((".swift", ".m", ".h")) or is_protected(path, prefixes):
            continue
        if path not in views:
            _, code, comments = source_views(diff.sources.get(path, text), swift=path.endswith(".swift"))
            views[path] = code.splitlines(), comments.splitlines()
        code_lines, comment_lines = views[path]
        index = line_no - 1
        code_line = code_lines[index] if 0 <= index < len(code_lines) else text
        comment_line = comment_lines[index] if 0 <= index < len(comment_lines) else ""
        for regex, why in patterns:
            candidate = comment_line if regex.pattern in {"swiftlint:disable", "swiftformat:disable"} else code_line
            if regex.search(candidate):
                hits.append((path, line_no, why, text.strip()))

    for path, line_no, why, text in hits:
        message = f"Supressão adicionada ({why}): {text}"
        if labels is None:
            report.notice(message, path, line_no)
        elif LABEL_EXCEPTION not in labels:
            report.error(
                f"{message}. Corrija o código em vez de desligar a verificação; se a exceção for "
                f"mesmo necessária, justifique no PR e uma pessoa adiciona o label '{LABEL_EXCEPTION}'.",
                path, line_no,
            )
        else:
            report.notice(f"{message} (aceita pelo label {LABEL_EXCEPTION})", path, line_no)


# ---------------------------------------------------------------- regra 4


TEST_DECL = re.compile(r"^\s*(@Test\b|func\s+test\w*\s*\()", re.MULTILINE)


def is_test_source(path: str) -> bool:
    # shortcut: counts declarations in conventional test paths, not compiler discovery; revisit if targets change.
    parts = Path(path).parts
    return any(part == "Tests" or part.endswith("Tests") for part in parts[:-1]) or Path(path).stem.endswith("Tests")


def count_tests(tree: str | None) -> int:
    """Conta testes em um commit (tree) ou na árvore de trabalho (None)."""
    total = 0
    if tree is None:
        files = git("ls-files", "--cached", "--others", "--exclude-standard").splitlines()
        for path in files:
            if path.endswith(".swift") and is_test_source(path) and (ROOT / path).exists():
                total += len(TEST_DECL.findall(source_views((ROOT / path).read_text(encoding="utf-8"))[1]))
        return total
    if tree == EMPTY_TREE:
        return 0
    for path in git("ls-tree", "-r", "--name-only", tree).splitlines():
        if path.endswith(".swift") and is_test_source(path):
            total += len(TEST_DECL.findall(source_views(git("show", f"{tree}:{path}"))[1]))
    return total


def check_test_count(report: Report, base: str, local: bool, labels: set[str] | None) -> None:
    merge_base = base if local or base == EMPTY_TREE else git("merge-base", base, "HEAD").strip()
    before, after = count_tests(merge_base), count_tests(None if local else "HEAD")
    if after >= before:
        return
    message = f"O número de testes caiu de {before} para {after}."
    if labels is None:
        report.notice(message)
    elif LABEL_EXCEPTION not in labels:
        report.error(f"{message} Remover testes exige revisão humana e o label '{LABEL_EXCEPTION}'.")


# ---------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["pr", "push", "local", "staged"], required=True)
    parser.add_argument("--base", default="")
    args = parser.parse_args()

    base = args.base
    if not base or set(base) == {"0"} or not ref_exists(base):
        if args.mode == "staged":
            base = "HEAD" if ref_exists("HEAD") else EMPTY_TREE
        elif args.mode == "local":
            base = "origin/main" if ref_exists("origin/main") else ("HEAD" if ref_exists("HEAD") else EMPTY_TREE)
        else:
            base = EMPTY_TREE

    labels: set[str] | None = None
    if args.mode == "pr":
        labels = set(json.loads(os.environ.get("PR_LABELS") or "[]"))

    report = Report()
    check_dependencies(report, staged=args.mode == "staged")
    if args.mode != "push":
        local = args.mode in ("local", "staged")
        diff = collect_diff(base, local=local, staged=args.mode == "staged")
        check_protected(report, diff, labels)
        check_suppressions(report, diff, labels)
        if args.mode != "staged":
            check_test_count(report, base, local, labels)

    for message in report.notices:
        print(f"aviso: {message}", file=sys.stderr)
    for message in report.errors:
        print(f"erro: {message}", file=sys.stderr)
    if report.errors:
        print(f"\n{len(report.errors)} violação(ões) de política.", file=sys.stderr)
        return 1
    print("Políticas OK.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
