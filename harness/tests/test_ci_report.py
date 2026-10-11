"""Run the actual workflow reporter offline with JSON results and a fake GitHub API."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
NODE = shutil.which("node")
WORKFLOW = ROOT / ".github/workflows/ios-tests.yml"
SCRIPT = textwrap.dedent(WORKFLOW.read_text().split("          script: |\n", 1)[1])
COLLECT = ROOT / "harness/ci-report.py"
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
        self.output = self.directory / "output"
        self.fixtures = self.directory / "fixtures.json"
        self.results = {
            "summary": {"passedTests": 3, "failedTests": 1, "skippedTests": 0},
            "tests": {"testNodes": [{"nodeType": "Test Suite", "duration": "1h", "children": [
                {"nodeType": "Test Case", "nodeIdentifier": "Suite/fast()", "result": "Passed", "duration": "0.001s"},
                {"nodeType": "Test Case", "nodeIdentifier": "Suite/slow()", "result": "Failed", "duration": "1m 2.5s",
                 "children": [{"nodeType": "Failure Message", "name": "failure"}]},
            ]}]},
            "coverage": {"targets": [
                {"name": "SeasoningManagerTests.xctest", "coveredLines": 99, "executableLines": 100,
                 "files": [{"path": "Test.swift", "coveredLines": 99, "executableLines": 100}]},
                {"name": "SeasoningManager.app", "coveredLines": 1, "executableLines": 2,
                 "files": [{"path": "src/SeasoningManager/App.swift", "coveredLines": 1, "executableLines": 2,
                            "functions": [{"name": "excluded implementation detail"}]}]},
            ]},
        }
        tool = self.directory / "xcrun"
        tool.write_text(
            "#!" + shutil.which("python3") + "\n"
            "import json, os, pathlib, sys\n"
            "with pathlib.Path(os.environ['TEST_CALLS']).open('a') as stream:\n"
            "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n"
            "if sys.argv[1] == os.environ.get('TEST_FAIL_TOOL'):\n"
            "    sys.exit(65)\n"
            "kind = 'coverage' if sys.argv[1] == 'xccov' else sys.argv[4]\n"
            "if kind == os.environ.get('TEST_BAD_KIND'):\n"
            "    print('{')\n"
            "else:\n"
            "    print(json.dumps(json.loads(pathlib.Path(os.environ['TEST_FIXTURES']).read_text())[kind]))\n",
            encoding="utf-8",
        )
        tool.chmod(0o755)
        self.env = dict(os.environ, RUNNER_TEMP=str(self.directory),
                        TEST_TARGET="SeasoningManagerTests", HARNESS_RESULT_BUNDLE=str(self.bundle),
                        TEST_CALLS=str(self.calls), TEST_FIXTURES=str(self.fixtures),
                        GITHUB_OUTPUT=str(self.output), GITHUB_RUN_ID="1234", GITHUB_RUN_ATTEMPT="2",
                        PATH=str(self.directory) + os.pathsep + os.environ["PATH"])

    def run_collection(self):
        self.fixtures.write_text(json.dumps(self.results), encoding="utf-8")
        self.output.unlink(missing_ok=True)
        return subprocess.run(
            [sys.executable, str(COLLECT)],
            env=self.env, text=True, capture_output=True, cwd=self.directory,
        )

    def report(self):
        key, raw = self.output.read_text().strip().split("=", 1)
        self.assertEqual(key, {"SeasoningManagerTests": "unit_report", "SeasoningManagerUITests": "ui_report"}[self.env["TEST_TARGET"]])
        return json.loads(raw)

    def test_success_passes_counts_app_files_and_individual_tests_without_attachments(self):
        result = self.run_collection()
        self.assertEqual(result.returncode, 0, result.stderr)
        report = self.report()
        self.assertEqual(report["summary"]["failedTests"], 1)
        self.assertEqual(report["coverage"]["coveredLines"], 1)
        self.assertEqual(len(report["coverage"]["files"]), 1)
        self.assertNotIn("functions", report["coverage"]["files"][0])
        self.assertEqual([(test["name"], test["seconds"]) for test in report["tests"]],
                         [("Suite/slow()", 62.5), ("Suite/fast()", 0.001)])
        self.assertEqual(report["runId"], "1234")
        self.assertEqual(report["attempt"], "2")
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertEqual(calls, [
            ["xcresulttool", "get", "test-results", "summary", "--path", str(self.bundle)],
            ["xcresulttool", "get", "test-results", "tests", "--path", str(self.bundle)],
            ["xccov", "view", "--report", "--json", str(self.bundle)],
        ])

    def test_failed_export_does_not_hide_failure_or_skip_other_reader(self):
        for tool, retained in (("xcresulttool", "coverage"), ("xccov", "summary")):
            with self.subTest(tool=tool):
                self.env["TEST_FAIL_TOOL"] = tool
                self.calls.unlink(missing_ok=True)
                result = self.run_collection()
                self.assertEqual(result.returncode, 1)
                self.assertEqual(len(self.calls.read_text().splitlines()), 3)
                self.assertIsInstance(self.report()[retained], dict)
                self.assertTrue(self.report()["errors"])

    def test_missing_bundle_is_explicit_and_does_not_launch_readers(self):
        self.bundle.rmdir()
        result = self.run_collection()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("unavailable", result.stdout)
        self.assertIsNone(self.report()["summary"])
        self.assertIsNone(self.report()["coverage"])
        self.assertIsNone(self.report()["tests"])
        self.assertFalse(self.calls.exists())

    def test_ui_job_emits_only_its_own_output_key(self):
        self.env["TEST_TARGET"] = "SeasoningManagerUITests"
        self.assertEqual(self.run_collection().returncode, 0)
        self.assertIsInstance(self.report()["summary"], dict)
        self.assertNotIn("unit_report=", self.output.read_text())

    def test_invalid_json_keeps_other_results_and_fails_collection(self):
        self.env["TEST_BAD_KIND"] = "tests"
        self.assertEqual(self.run_collection().returncode, 1)
        report = self.report()
        self.assertIsNone(report["tests"])
        self.assertEqual(report["errors"], ["tests"])
        self.assertEqual(report["summary"]["passedTests"], 3)
        self.assertEqual(report["coverage"]["coveredLines"], 1)

    def test_unknown_and_zero_duration_are_distinct(self):
        self.results["tests"]["testNodes"] = [
            {"nodeType": "Test Case", "nodeIdentifier": value, "duration": value}
            for value in ("unknown", "0s", "1d 2h 3m 4s", "-1s", "NaN", None)
        ]
        self.assertEqual(self.run_collection().returncode, 0)
        times = {test["name"]: test["seconds"] for test in self.report()["tests"]}
        self.assertEqual(times["0s"], 0)
        self.assertEqual(times["1d 2h 3m 4s"], 93784)
        for value in ("unknown", "-1s", "NaN", None):
            self.assertIsNone(times[value])

    def test_large_output_preserves_worst_files_and_slowest_tests_and_reports_omissions(self):
        self.results["coverage"]["targets"][1]["files"] = [
            {"path": f"{index}-" + "調味料" * 100, "coveredLines": index, "executableLines": 200}
            for index in range(200)
        ]
        self.results["tests"]["testNodes"] = [
            {"nodeType": "Test Case", "nodeIdentifier": f"{index}-" + "調味料" * 100,
             "result": "Passed", "duration": f"{index}s"}
            for index in range(200)
        ]
        self.assertEqual(self.run_collection().returncode, 0)
        self.assertLessEqual(len(self.output.read_bytes()), 60000 + len("unit_report=\n"))
        report = self.report()
        self.assertGreater(report["omitted"]["files"], 0)
        self.assertGreater(report["omitted"]["tests"], 0)
        self.assertEqual(report["coverage"]["files"][0]["coveredLines"], 0)
        self.assertEqual(report["tests"][0]["seconds"], 199)


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
        self.env = dict(os.environ, GITHUB_RUN_ID="1234", GITHUB_RUN_ATTEMPT="2")
        self.reports = {}
        self.raw_reports = {}
        for target in ("SeasoningManagerTests", "SeasoningManagerUITests"):
            self.reports[target] = {"runId": "1234", "attempt": "2", "errors": [], "omitted": {}}
            self.write_report(target, "summary", {
                "passedTests": 5, "failedTests": 1, "skippedTests": 2,
                "totalTestCount": 8,
            })
            self.write_report(target, "coverage", {
                "coveredLines": 25, "executableLines": 100,
                "files": [
                    {"path": "/Users/runner/work/repo/repo/src/SeasoningManager/High.swift", "coveredLines": 80, "executableLines": 100},
                    {"path": "src/SeasoningManager/Low.swift", "coveredLines": 79, "executableLines": 100},
                    {"path": "src/SeasoningManager/Zero.swift", "coveredLines": 0, "executableLines": 100},
                    {"path": "src/SeasoningManager/Empty.swift", "coveredLines": 0, "executableLines": 0},
                ],
            })
            self.write_report(target, "tests", [
                {"name": "Suite/fast()", "result": "Passed", "seconds": 0.001},
                {"name": "Suite/slow()", "result": "Failed", "seconds": 62.5},
                {"name": "Suite/skipped()", "result": "Skipped", "seconds": 999},
                {"name": "Suite/unknown()", "result": "Passed", "seconds": None},
            ])

    def write_report(self, target, name, value):
        self.reports[target][name] = value

    def run_report(self):
        env = dict(self.env)
        for target, variable in (("SeasoningManagerTests", "UNIT_REPORT"), ("SeasoningManagerUITests", "UI_REPORT")):
            env[variable] = self.raw_reports.get(target, json.dumps(self.reports.get(target)))
        request = {
            "script": SCRIPT, "context": self.context, "current": self.current,
            "comments": self.comments, "jobs": self.jobs,
        }
        result = subprocess.run(
            [NODE, "-e", RUNNER], input=json.dumps(request), text=True,
            capture_output=True, cwd=self.directory, env=env,
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

    def test_highlights_low_coverage_and_slowest_tests_before_collapsed_details(self):
        body = self.run_report()["summary"]
        highlights, details = body.split("<details>", 1)
        low = highlights.split("#### 低カバレッジ", 1)[1].split("#### 遅いテスト", 1)[0]
        self.assertIn("Low.swift | 79.00%", low)
        self.assertIn("Zero.swift | 0.00%", low)
        self.assertLess(low.index("Zero.swift"), low.index("Low.swift"))
        self.assertNotIn("High.swift", low)  # Exactly 80% is excluded.
        self.assertNotIn("Empty.swift", low)
        slow = highlights.split("#### 遅いテスト", 1)[1]
        self.assertLess(slow.index("Suite/slow()"), slow.index("Suite/fast()"))
        self.assertNotIn("Suite/skipped()", slow)
        self.assertNotIn("Suite/unknown()", slow)
        self.assertIn("High.swift | 80.00%", details)
        self.assertIn("Empty.swift | 未取得", details)
        self.assertIn("Suite/skipped() | スキップ | 未実施", details)
        self.assertIn("Suite/unknown() | 成功 | 未取得", details)
        self.assertNotIn("/Users/runner", body)
        self.assertEqual(body.count("<details>"), 4)
        self.assertEqual(body.count("</details>"), 4)
        self.assertNotIn("<details open", body)

    def test_only_ten_slowest_tests_are_highlighted_but_all_remain_in_details(self):
        self.write_report("SeasoningManagerTests", "tests", [
            {"name": f"Suite/test{index:02}()", "result": "Passed", "seconds": index}
            for index in range(12)
        ])
        body = self.run_report()["summary"]
        highlights, details = body.split("<details>", 1)
        slow = highlights.split("#### 遅いテスト", 1)[1].split("**UI tests**", 1)[0]
        self.assertEqual(slow.count("Suite/test"), 10)
        self.assertLess(slow.index("test11"), slow.index("test10"))
        self.assertNotIn("test01", slow)
        self.assertIn("test01", details)
        self.assertIn("test00() | 成功 | 0.000秒", details)

    def test_names_cannot_inject_html_tables_or_markdown(self):
        name = "evil|`[link](url)\n</details><script>&*bold*"
        self.write_report("SeasoningManagerTests", "tests", [{"name": name, "result": "Passed", "seconds": 1}])
        self.write_report("SeasoningManagerTests", "coverage", {
            "coveredLines": 1, "executableLines": 2,
            "files": [{"path": name + ".swift", "coveredLines": 1, "executableLines": 2}],
        })
        body = self.run_report()["summary"]
        self.assertNotIn("<script>", body)
        self.assertNotIn("evil|", body)
        self.assertNotIn("[link]", body)
        self.assertNotIn("*bold*", body)
        self.assertIn("evil&#124;&#96;&#91;link&#93;", body)
        self.assertEqual(body.count("</details>"), 4)

    def test_large_details_fit_comment_limit_and_explicitly_report_omissions(self):
        for target in self.reports:
            self.write_report(target, "tests", [
                {"name": f"{index}:" + "&" * 240, "result": "Passed", "seconds": index}
                for index in range(60)
            ])
            self.write_report(target, "coverage", {
                "coveredLines": 1, "executableLines": 2,
                "files": [{"path": f"{index}:" + "&" * 240, "coveredLines": 1, "executableLines": 2}
                          for index in range(60)],
            })
        self.reports["SeasoningManagerTests"]["omitted"] = {"files": 20, "tests": 30}
        body = self.run_report()["summary"]
        self.assertLess(len(body), 60000)
        self.assertIn("コメントの文字数上限", body)
        self.assertIn("ファイル詳細を20件省略", body)
        self.assertIn("テスト詳細を30件省略", body)
        self.assertEqual(body.count("<details>"), body.count("</details>"))

    def test_wrong_run_or_attempt_outputs_are_unavailable_even_if_job_exists(self):
        for field, value in (("attempt", "1"), ("runId", "1233")):
            with self.subTest(field=field):
                report = self.reports["SeasoningManagerTests"]
                previous = report[field]
                report[field] = value
                self.assertIn("| Unit tests | 成功 | 未取得 |", self.run_report()["summary"])
                report[field] = previous

    def test_missing_bundle_and_failed_setup_are_not_zero_tests_or_success(self):
        self.reports.clear()
        self.jobs[0]["conclusion"] = "failure"
        self.jobs[0]["steps"] = []
        result = self.run_report()
        self.assertIn("| Unit tests | 失敗 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |", result["summary"])

    def test_malformed_data_and_zero_denominator_are_unavailable(self):
        self.write_report("SeasoningManagerTests", "summary", {
            "passedTests": "<script>bad</script>", "failedTests": -1, "skippedTests": None,
        })
        self.write_report("SeasoningManagerTests", "coverage", {
            "coveredLines": 0, "executableLines": 0,
        })
        result = self.run_report()
        self.assertIn("| Unit tests | 成功 | 未取得 | 未取得 | 未取得 | 未取得 |", result["summary"])
        self.assertNotIn("<script>", result["summary"])

    def test_invalid_json_does_not_prevent_failure_report(self):
        self.raw_reports["SeasoningManagerTests"] = "{"
        self.assertIn("| Unit tests | 成功 | 未取得 |", self.run_report()["summary"])

    def test_null_coverage_does_not_abort_comment(self):
        self.write_report("SeasoningManagerTests", "coverage", None)
        result = self.run_report()
        self.assertIn("| Unit tests | 成功 | 5 | 1 | 2 | 未取得 |", result["summary"])
        self.assertEqual(len(self.mutations(result)), 1)

    def test_partial_rerun_does_not_reuse_previous_attempt_data(self):
        self.jobs.pop()
        body = self.run_report()["summary"]
        self.assertIn("| UI tests | 未完了・未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 | 未取得 |", body)
        self.assertIn("今回の attempt", body)

    def test_zero_percent_is_measured_when_executable_lines_exist(self):
        self.write_report("SeasoningManagerTests", "coverage", {
            "coveredLines": 0, "executableLines": 100,
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

    def test_collection_failure_is_explicit_and_keeps_available_values(self):
        self.reports["SeasoningManagerTests"]["errors"] = ["tests"]
        self.write_report("SeasoningManagerTests", "tests", None)
        body = self.run_report()["summary"]
        self.assertIn("結果収集の一部に失敗", body)
        self.assertIn("テスト別実行時間は未取得", body)
        self.assertIn("25.00% (25/100行)", body)

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
