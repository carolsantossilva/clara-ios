"""Keep the traced CodeQL Swift build limited to compiling the sources."""
from pathlib import Path
import json
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]
TEXT = (ROOT / ".github/workflows/codeql.yml").read_text()
TRACING_CONFIG = ".github/codeql/skip-swiftpm-manifests.lua"


def step(name):
    match = re.search(rf"^      - name: {name}\n(.*?)(?=^      - )", TEXT, re.M | re.S)
    return match.group(1) if match else None


def swift_init_step():
    swift = TEXT[TEXT.index("\n  swift:\n"):]
    match = re.search(r"^      - uses: github/codeql-action/init@.*?(?=^      - )", swift, re.M | re.S)
    return match.group(0) if match else None


class CodeQLBuildTests(unittest.TestCase):
    def test_swift_build_compiles_a_single_simulator_architecture(self):
        build = step("Build")
        self.assertIsNotNone(build, "CodeQL Swift job has no step named Build")
        self.assertIn('-destination "generic/platform=iOS Simulator"', build)
        self.assertRegex(build, r"(?m)^\s+ARCHS=arm64 \\$")

    def test_tracer_skips_swiftpm_manifests_through_an_extra_config(self):
        init = swift_init_step()
        self.assertIsNotNone(init, "CodeQL Swift job has no init step")
        self.assertIn("languages: swift", init)
        match = re.search(r"^          CODEQL_ACTION_EXTRA_OPTIONS: '(.*)'$", init, re.M)
        self.assertIsNotNone(match, "Swift init does not set CODEQL_ACTION_EXTRA_OPTIONS")
        options = json.loads(match.group(1))
        self.assertEqual(options, {"database": {"init": [
            f"--extra-tracing-config=${{{{ github.workspace }}}}/{TRACING_CONFIG}"]}})

    def test_extra_config_only_prepends_a_manifest_matcher_to_swift(self):
        config = (ROOT / TRACING_CONFIG).read_text()
        self.assertIn("function GetCompatibleVersions()\n    return { '1.0.0' }", config)
        self.assertIn("GetRegisteredMatchers('swift')", config)
        self.assertIn("return { swift = matchers }", config)
        self.assertIn("compilerName ~= 'swift-frontend'", config)
        self.assertIn("'-apple-macos'", config)
        self.assertIn("'/Package[^/]*%.swift$'", config)
        self.assertIn("return macOSTarget and manifest", config)
        self.assertNotIn("invocation =", config)

    def test_build_has_no_separate_package_resolution(self):
        self.assertIsNone(step("Resolve packages"))


if __name__ == "__main__":
    unittest.main()
