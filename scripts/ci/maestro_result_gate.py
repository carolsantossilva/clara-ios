#!/usr/bin/env python3
"""Fail closed when Maestro reports no discovered flows."""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def check_results(path):
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError) as error:
        raise ValueError("Maestro did not produce a readable JUnit report") from error
    executed = sum(
        1 for element in root.iter()
        if element.tag.rsplit("}", 1)[-1] == "testcase"
        and not any(child.tag.rsplit("}", 1)[-1] == "skipped" for child in element.iter())
    )
    if executed == 0:
        raise ValueError("Maestro selected no flows")


if __name__ == "__main__":
    try:
        check_results(Path(sys.argv[1]))
    except (IndexError, ValueError) as error:
        sys.exit(str(error))
