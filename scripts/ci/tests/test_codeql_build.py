"""Keep the CodeQL Swift build from compiling every source once per simulator architecture."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]


class CodeQLBuildTests(unittest.TestCase):
    def test_swift_build_compiles_a_single_simulator_architecture(self):
        text = (ROOT / ".github/workflows/codeql.yml").read_text()
        build = re.search(r"^      - name: Build\n(.*?)(?=^      - )", text, re.M | re.S).group(1)
        self.assertIn('-destination "generic/platform=iOS Simulator"', build)
        self.assertRegex(build, r"(?m)^\s+ARCHS=arm64 \\$")


if __name__ == "__main__":
    unittest.main()
