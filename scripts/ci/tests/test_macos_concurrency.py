"""Keep macOS checks queued across PRs without discarding pending jobs."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[3]


class MacOSConcurrencyTests(unittest.TestCase):
    def test_all_ci_and_codeql_macos_jobs_share_a_preserving_queue(self):
        found = set()
        for workflow in ("ci", "codeql"):
            text = (ROOT / ".github/workflows" / f"{workflow}.yml").read_text()
            jobs = text.split("\njobs:\n", 1)[1]
            for match in re.finditer(r"^  ([\w-]+):\n(.*?)(?=^  [\w-]+:\n|\Z)", jobs, re.M | re.S):
                name, body = match.groups()
                if not re.search(r"^    runs-on: macos-", body, re.M):
                    continue
                found.add((workflow, name))
                with self.subTest(workflow=workflow, job=name):
                    self.assertIn("    concurrency:\n      group: macos-ci\n      queue: max\n", body)
                    self.assertNotIn("cancel-in-progress: true", body)
        self.assertEqual(found, {
            ("ci", "lint"), ("ci", "test"), ("ci", "package"), ("ci", "maestro"),
            ("codeql", "swift"),
        })

    def test_codeql_cancels_obsolete_runs_of_the_same_pr_only(self):
        text = (ROOT / ".github/workflows/codeql.yml").read_text().split("\njobs:\n", 1)[0]
        self.assertIn(
            "concurrency:\n"
            "  group: codeql-${{ github.event.pull_request.number || github.ref }}\n"
            "  cancel-in-progress: true\n", text,
        )


if __name__ == "__main__":
    unittest.main()
