"""Run the actual workflow reporter offline with JSON results and a fake GitHub API."""

import json
import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
NODE = shutil.which("node")
WORKFLOW = ROOT / ".github/workflows/ios-tests.yml"
SCRIPT = textwrap.dedent(WORKFLOW.read_text().split("          script: |\n", 1)[1])
COLLECT = textwrap.dedent(
    WORKFLOW.read_text().split("      - name: Collect test counts and app coverage\n", 1)[1]
    .split("        run: |\n", 1)[1].split("\n      - name: Upload test report", 1)[0]
)
MARKER = "<!-- seasoning-ios-test-report -->"
RUNNER = """
const fs = require('node:fs');
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const calls = [];
let summary = '';
const github = {
  rest: {
    actions: { listJobsForWorkflowRunAttempt: 'jobs' },
    pulls: { get: async args => ({ data: input.current }) },
    issues: {
      listComments: 'comments',
      updateComment: async args => calls.push({ operation: 'update', ...args }),
      createComment: async args => calls.push({ operation: 'create', ...args })
    }
  },
  paginate: async (route, args) => {
    calls.push({ operation: route, ...args });
    if (route === 'jobs') {
      return input.jobs;
    }
    if (route === 'comments') {
      return input.comments;
    }
    throw Error('Unexpected API');
  }
};
const core = {
  info: message => {},
  summary: {
    addRaw: body => { summary = body; return core.summary; },
    write: async () => {}
  }
};
const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
(async () => {
  await new AsyncFunction('github', 'context', 'core', 'require', input.script)(
    github, input.context, core, require
  );
  process.stdout.write(JSON.stringify({ calls, summary }));
})().catch(error => { console.error(error); process.exitCode = 1; });
"""


class CICollectionTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.directory = Path(self.workspace.name)
        self.bundle = self.directory / "test results.xcresult"
        self.bundle.mkdir()
        self.calls = self.directory / "calls.jsonl"
        tool = self.directory / "xcrun"
        tool.write_text(
            "#!" + shutil.which("python3") + "\n"
            "import json, os, pathlib, sys\n"
            "with pathlib.Path(os.environ['TEST_CALLS']).open('a') as stream:\n"
            "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "if sys.argv[1] == os.environ.get('TEST_FAIL_TOOL'):\n"
            "    sys.exit(65)\n"
            "if sys.argv[1] == 'xcresulttool':\n"
            "    print(json.dumps({'passedTests': 3, 'failedTests': 1, 'skippedTests': 0}))\n"
            "if sys.argv[1] == 'xccov':\n"
            "    print(json.dumps({'targets': [{'name': 'SeasoningManager.app', 'coveredLines': 1, 'executableLines': 2}]}))\n",
            encoding="utf-8",
        )
        tool.chmod(0o755)
        self.env = dict(os.environ, RUNNER_TEMP=str(self.directory),
                        TEST_TARGET="SeasoningManagerTests", HARNESS_RESULT_BUNDLE=str(self.bundle),
                        TEST_CALLS=str(self.calls), PATH=str(self.directory) + os.pathsep + os.environ["PATH"])
        self.report = self.directory / "test-reports/SeasoningManagerTests"

    def run_collection(self):
        return subprocess.run(
            [shutil.which("bash"), "-e", "-o", "pipefail", "-c", COLLECT],
            env=self.env, text=True, capture_output=True, cwd=self.directory,
        )

    def test_success_exports_both_reports_with_bundle_path_as_one_argument(self):
        result = self.run_collection()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads((self.report / "summary.json").read_text())["failedTests"], 1)
        self.assertEqual(json.loads((self.report / "coverage.json").read_text())["targets"][0]["coveredLines"], 1)
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls, [
            ["xcresulttool", "get", "test-results", "summary", "--path", str(self.bundle)],
            ["xccov", "view", "--report", "--json", str(self.bundle)],
        ])

    def test_failed_export_does_not_hide_failure_or_skip_other_reader(self):
        for tool, retained in (("xcresulttool", "coverage"), ("xccov", "summary")):
            with self.subTest(tool=tool):
                self.env["TEST_FAIL_TOOL"] = tool
                self.calls.unlink(missing_ok=True)
                result = self.run_collection()
                self.assertEqual(result.returncode, 1)
                self.assertEqual(len(self.calls.read_text().splitlines()), 2)
                self.assertIsInstance(json.loads((self.report / f"{retained}.json").read_text()), dict)

    def test_missing_bundle_is_explicit_and_does_not_launch_readers(self):
        self.bundle.rmdir()
        result = self.run_collection()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("unavailable", (self.report / "unavailable.txt").read_text())
        self.assertFalse(self.calls.exists())


@unittest.skipUnless(NODE, "Node.js required for the CI reporter's JavaScript")
class CIReportTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.directory = Path(self.workspace.name)
        self.head = "a" * 40
        self.context = {
            "repo": {"owner": "DIO0550", "repo": "seasoning-management-iOS"},
            "sha": "b" * 40,
            "serverUrl": "https://github.com",
            "payload": {
                "pull_request": {
                    "number": 108,
                    "head": {
                        "sha": self.head,
                        "repo": {"full_name": "DIO0550/seasoning-management-iOS"},
                    },
                }
            },
        }
        self.current = {"state": "open", "head": {"sha": self.head}}
        self.comments = []
        self.jobs = [
            {
                "name": name,
                "conclusion": "success",
                "started_at": "2026-10-10T14:00:00Z",
                "completed_at": "2026-10-10T14:06:00Z",
                "steps": [{
                    "name": "Run tests",
                    "conclusion": "success",
                    "started_at": "2026-10-10T14:02:00Z",
                    "completed_at": "2026-10-10T14:04:30Z",
                }],
            }
            for name in ("Unit tests", "UI tests")
        ]
        self.env = dict(os.environ, GITHUB_RUN_ID="1234", GITHUB_RUN_ATTEMPT="2",
                        REPORT_DOWNLOAD_OUTCOME="success")
        for target in ("SeasoningManagerTests", "SeasoningManagerUITests"):
            self.write_report(target, "summary", {
                "passedTests": 5, "failedTests": 1, "skippedTests": 2,
                "totalTestCount": 8,
            })
            self.write_report(target, "coverage", {
                "coveredLines": 999, "executableLines": 1000,
                "targets": [
                    {"name": "SeasoningManagerTests.xctest", "coveredLines": 99, "executableLines": 100},
                    {"name": "SeasoningManager.app", "coveredLines": 25, "executableLines": 100},
                ],
            })

    def write_report(self, target, name, value):
        directory = self.directory / "reports" / target
        directory.mkdir(parents=True, exist_ok=True)
        (directory / f"{name}.json").write_text(json.dumps(value), encoding="utf-8")

    def run_report(self):
        request = {
            "script": SCRIPT, "context": self.context, "current": self.current,
            "comments": self.comments, "jobs": self.jobs,
        }
        result = subprocess.run(
            [NODE, "-e", RUNNER], input=json.dumps(request), text=True,
            capture_output=True, cwd=self.directory, env=self.env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def mutations(self, result):
        return [call for call in result["calls"] if call["operation"] in ("create", "update")]

    def test_report_posts_counts_app_coverage_and_separate_durations(self):
        result = self.run_report()
        body = self.mutations(result)[0]["body"]
        self.assertIn("| Unit tests | 成功 | 5 | 1 | 2 | 25.00% (25/100行) | 2分30秒 | 6分0秒 |", body)
        self.assertIn("| UI tests | 成功 | 5 | 1 | 2 | 25.00% (25/100行)", body)
        self.assertNotIn("99.00%", body)
        self.assertIn(self.head, body)
        self.assertIn("/actions/runs/1234/attempts/2", body)
        self.assertEqual(body, result["summary"])
        jobs_request = result["calls"][0]
        self.assertEqual(jobs_request["attempt_number"], 2)

    def test_missing_bundle_and_failed_setup_are_not_zero_tests_or_success(self):
        shutil.rmtree(self.directory / "reports")
        self.jobs[0]["conclusion"] = "failure"
        self.jobs[0]["steps"] = []
        result = self.run_report()
        self.assertIn("| Unit tests | 失敗 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |", result["summary"])

    def test_malformed_data_and_zero_denominator_are_unavailable(self):
        self.write_report("SeasoningManagerTests", "summary", {
            "passedTests": "<script>bad</script>", "failedTests": -1, "skippedTests": None,
        })
        self.write_report("SeasoningManagerTests", "coverage", {
            "targets": [{"name": "SeasoningManager.app", "coveredLines": 0, "executableLines": 0}],
        })
        result = self.run_report()
        self.assertIn("| Unit tests | 成功 | 未取得 | 未取得 | 未取得 | 未取得 |", result["summary"])
        self.assertNotIn("<script>", result["summary"])

    def test_invalid_json_does_not_prevent_failure_report(self):
        path = self.directory / "reports/SeasoningManagerTests/summary.json"
        path.write_text("{", encoding="utf-8")
        self.assertIn("| Unit tests | 成功 | 未取得 |", self.run_report()["summary"])

    def test_null_coverage_target_does_not_abort_comment(self):
        self.write_report("SeasoningManagerTests", "coverage", {"targets": [None]})
        result = self.run_report()
        self.assertIn("| Unit tests | 成功 | 5 | 1 | 2 | 未取得 |", result["summary"])
        self.assertEqual(len(self.mutations(result)), 1)

    def test_partial_rerun_does_not_reuse_previous_attempt_data(self):
        self.jobs.pop()
        shutil.rmtree(self.directory / "reports/SeasoningManagerUITests")
        body = self.run_report()["summary"]
        self.assertIn("| UI tests | 未完了・未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |", body)
        self.assertIn("今回の attempt", body)

    def test_zero_percent_is_measured_when_executable_lines_exist(self):
        self.write_report("SeasoningManagerTests", "coverage", {
            "targets": [{"name": "SeasoningManager.app", "coveredLines": 0, "executableLines": 100}],
        })
        self.assertIn("0.00% (0/100行)", self.run_report()["summary"])

    def test_rerun_updates_only_the_bot_comment(self):
        self.comments = [
            {"id": 1, "user": {"login": "DIO0550"}, "body": MARKER},
            {"id": 2, "user": {"login": "github-actions[bot]"},
             "body": MARKER + "\n<!-- ios-test-run:1234:1 -->"},
        ]
        mutation = self.mutations(self.run_report())[0]
        self.assertEqual(mutation["operation"], "update")
        self.assertEqual(mutation["comment_id"], 2)

    def test_older_run_or_attempt_does_not_overwrite_newer_results(self):
        for run, attempt in ((1235, 1), (1234, 3)):
            with self.subTest(run=run, attempt=attempt):
                self.comments = [{"id": 2, "user": {"login": "github-actions[bot]"},
                                  "body": MARKER + f"\n<!-- ios-test-run:{run}:{attempt} -->"}]
                self.assertEqual(self.mutations(self.run_report()), [])

    def test_changed_head_or_closed_pr_only_writes_step_summary(self):
        for current in ({"state": "open", "head": {"sha": "c" * 40}},
                        {"state": "closed", "head": {"sha": self.head}}):
            with self.subTest(current=current):
                self.current = current
                result = self.run_report()
                self.assertEqual(self.mutations(result), [])
                self.assertIn("iOS CI 検証結果", result["summary"])

    def test_fork_only_writes_step_summary(self):
        self.context["payload"]["pull_request"]["head"]["repo"]["full_name"] = "fork/seasoning-management-iOS"
        result = self.run_report()
        self.assertEqual(self.mutations(result), [])
        self.assertIn("25.00%", result["summary"])

    def test_download_failure_is_explicit(self):
        self.env["REPORT_DOWNLOAD_OUTCOME"] = "failure"
        self.assertIn("レポートのダウンロードに失敗", self.run_report()["summary"])

    def test_skipped_step_and_unknown_job_are_not_measured_zero_seconds(self):
        self.jobs[0]["steps"][0]["conclusion"] = "skipped"
        self.jobs.pop()
        body = self.run_report()["summary"]
        self.assertIn("| 未実施 | 6分0秒 |", body)
        self.assertIn("| UI tests | 未完了・未取得 |", body)

    def test_invalid_or_negative_timestamps_are_unavailable(self):
        self.jobs[0]["completed_at"] = "invalid"
        self.jobs[1]["completed_at"] = "2026-10-10T13:00:00Z"
        body = self.run_report()["summary"]
        self.assertEqual(body.count("| 2分30秒 | 未取得 |"), 2)


if __name__ == "__main__":
    unittest.main()
