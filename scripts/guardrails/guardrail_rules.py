"""Shared policy data; callers retain their own enforcement decisions."""
from __future__ import annotations

from pathlib import Path


def read_list(path: Path, *, missing_ok: bool = False) -> list[str]:
    """Read non-comment entries without changing regexes or tab-separated fields."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        if missing_ok:
            return []
        raise
    return [line for line in lines if line.strip() and not line.lstrip().startswith("#")]


def is_protected(path: str, prefixes: list[str]) -> bool:
    """Match a repository-relative path against exact files or directory prefixes."""
    return any(path == prefix or (prefix.endswith("/") and path.startswith(prefix)) for prefix in prefixes)
