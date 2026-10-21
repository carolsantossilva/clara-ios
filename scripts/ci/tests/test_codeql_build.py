"""Keep the traced CodeQL Swift build limited to compiling the sources."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
TEXT = (ROOT / ".github/workflows/codeql.yml").read_text()


def step(name):
    match = re.search(rf"^      - name: {name}\n(.*?)(?=^      - )", TEXT, re.M | re.S)
    return match.group(1) if match else None


class CodeQLBuildTests(unittest.TestCase):
    def test_swift_build_compiles_a_single_simulator_architecture(self):
        build = step("Build")
        self.assertIsNotNone(build, "CodeQL Swift job has no step named Build")
        self.assertIn('-destination "generic/platform=iOS Simulator"', build)
        self.assertRegex(build, r"(?m)^\s+ARCHS=arm64 \\$")

    def test_packages_resolve_before_the_tracer_into_the_build_derived_data(self):
        resolve, build = step("Resolve packages"), step("Build")
        self.assertIsNotNone(resolve, "CodeQL Swift job has no step named Resolve packages")
        swift = TEXT[TEXT.index("\n  swift:\n"):]
        self.assertLess(swift.index("      - name: Resolve packages\n"),
                        swift.index("github/codeql-action/init@"))
        self.assertIn("xcodebuild -resolvePackageDependencies", resolve)
        for line in ('if [[ "$APP" == "true" ]]; then target=(-project Clara.xcodeproj -scheme Clara); \\',
                     "else cd Packages/ClaraKit; target=(-scheme ClaraKit-Package); fi",
                     '-derivedDataPath "$GITHUB_WORKSPACE/build/dd"',
                     "APP: ${{ needs.detect.outputs.app }}"):
            with self.subTest(line=line):
                self.assertIn(line, resolve)
                self.assertIn(line, build)


if __name__ == "__main__":
    unittest.main()
