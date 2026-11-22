"""Run the actual workflow reporter offline with JSON results and a fake GitHub API."""

import json
import os
import re
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
UI_SOURCES = ROOT / "src/SeasoningManager/SeasoningManagerUITests"
REPORTS = (
    ("Unit tests", "Unit", "UNIT_REPORT"),
    ("UI tests (商品1)", "UI(商品1)", "UI_PRODUCT_1_REPORT"),
    ("UI tests (商品2)", "UI(商品2)", "UI_PRODUCT_2_REPORT"),
    ("UI tests (在庫1)", "UI(在庫1)", "UI_INVENTORY_1_REPORT"),
    ("UI tests (その他)", "UI(その他)", "UI_REST_REPORT"),
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
                        HARNESS_REPORT_KEY="unit_report", HARNESS_RESULT_BUNDLE=str(self.bundle),
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
        self.assertEqual(key, self.env["HARNESS_REPORT_KEY"])
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
        self.env["HARNESS_REPORT_KEY"] = "ui_rest_report"
        self.assertEqual(self.run_collection().returncode, 0)
        self.assertIsInstance(self.report()["summary"], dict)
        self.assertNotIn("unit_report=", self.output.read_text())

    def test_invalid_report_key_writes_nothing_and_does_not_read_results(self):
        for key in (None, "", "unit", "Unit_report", "_report", "1_report", "ui-rest_report",
                    "unit_report\n", "unit_report=x", "unit_report\nother_report"):
            with self.subTest(key=key):
                if key is None:
                    self.env.pop("HARNESS_REPORT_KEY")
                else:
                    self.env["HARNESS_REPORT_KEY"] = key
                result = self.run_collection()
                self.assertEqual(result.returncode, 2)
                self.assertIn("HARNESS_REPORT_KEY", result.stderr)
                self.assertFalse(self.output.exists())
                self.assertFalse(self.calls.exists())

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
            for name, _, _ in REPORTS
        ]
        self.build_job = {
            "name": "Build for testing",
            "conclusion": "success",
            "started_at": "2026-10-10T13:50:00Z",
            "completed_at": "2026-10-10T13:54:00Z",
            "steps": [{
                "name": "Build for testing",
                "conclusion": "success",
                "started_at": "2026-10-10T13:50:30Z",
                "completed_at": "2026-10-10T13:53:45Z",
            }],
        }
        self.env = dict(os.environ, GITHUB_RUN_ID="1234", GITHUB_RUN_ATTEMPT="2")
        self.reports = {}
        self.raw_reports = {}
        for _, _, target in REPORTS:
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
        for _, _, variable in REPORTS:
            env[variable] = self.raw_reports.get(variable, json.dumps(self.reports.get(variable)))
        jobs = self.jobs + ([self.build_job] if self.build_job else [])
        request = {
            "script": SCRIPT, "context": self.context, "current": self.current,
            "comments": self.comments, "jobs": jobs,
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
        for _, name, _ in REPORTS:
            self.assertIn(f"| {name} | ✅ 成功 | 5 | 1 | 2 |", body)
            self.assertIn(f"| {name} | 🟠 25.00% (25/100行) |", body)
            self.assertIn(f"| {name} | 2分30秒 | 6分0秒 |", body)
        self.assertIn("| ビルド | ✅ 成功 | - | - | - |", body)
        self.assertIn("| ビルド | 3分15秒 | 4分0秒 |", body)
        self.assertNotIn("| ビルド | ⚪", body.split("#### 📊 カバレッジ", 1)[1])  # No coverage row.
        self.assertLess(body.index("#### 🧪 テスト結果"), body.index("#### 📊 カバレッジ"))
        self.assertLess(body.index("#### 📊 カバレッジ"), body.index("#### ⏱️ 実行時間"))
        self.assertIn("| 検証 | テスト | ジョブ全体 |", body)
        self.assertNotIn("ビルド＋テスト", body)
        self.assertTrue(body.rstrip().endswith("</details>"))
        self.assertNotIn("両者を合算", body)
        self.assertNotIn("99.00%", body)
        self.assertIn(self.head, body)
        self.assertIn("/actions/runs/1234/attempts/2", body)
        self.assertEqual(body, result["summary"])
        jobs_request = result["calls"][0]
        self.assertEqual(jobs_request["attempt_number"], 2)

    def test_highlights_low_coverage_and_slowest_tests_before_collapsed_details(self):
        body = self.run_report()["summary"]
        coverage, times = body.split("#### ⏱️ 実行時間", 1)
        low, coverage_details = coverage.split("<details>", 1)
        low = low.split("##### 🟠 80%未満", 1)[1]
        slow, test_details = times.split("<details>", 1)
        slow = slow.split("##### 🐢 遅いテスト", 1)[1]
        details = coverage_details + test_details
        self.assertIn("Low.swift | 🟠 79.00%", low)
        self.assertIn("Zero.swift | 🟠 0.00%", low)
        self.assertLess(low.index("Zero.swift"), low.index("Low.swift"))
        self.assertNotIn("High.swift", low)  # Exactly 80% is excluded.
        self.assertNotIn("Empty.swift", low)
        self.assertLess(slow.index("Suite/slow()"), slow.index("Suite/fast()"))
        self.assertNotIn("Suite/skipped()", slow)
        self.assertNotIn("Suite/unknown()", slow)
        self.assertIn("High.swift | 🟢 80.00%", details)
        self.assertIn("Empty.swift | ⚪ 未取得", details)
        self.assertIn("Suite/skipped() | ⏭️ スキップ | 未実施", details)
        self.assertIn("Suite/unknown() | ✅ 成功 | 未取得", details)
        self.assertNotIn("/Users/runner", body)
        self.assertEqual(body.count("<details>"), 2 * len(REPORTS))
        self.assertEqual(body.count("</details>"), 2 * len(REPORTS))
        self.assertNotIn("<details open", body)

    def test_only_ten_slowest_tests_are_highlighted_but_all_remain_in_details(self):
        self.write_report("UNIT_REPORT", "tests", [
            {"name": f"Suite/test{index:02}()", "result": "Passed", "seconds": index}
            for index in range(12)
        ])
        body = self.run_report()["summary"]
        times = body.split("#### ⏱️ 実行時間", 1)[1]
        highlights, details = times.split("<details>", 1)
        slow = highlights.split("##### 🐢 遅いテスト", 1)[1].split("**UI(商品1)**", 1)[0]
        self.assertEqual(slow.count("Suite/test"), 10)
        self.assertLess(slow.index("test11"), slow.index("test10"))
        self.assertNotIn("test01", slow)
        self.assertIn("test01", details)
        self.assertIn("test00() | ✅ 成功 | 0.000秒", details)

    def test_unmeasured_files_are_not_marked_as_no_low_coverage(self):
        self.write_report("UNIT_REPORT", "coverage", {
            "coveredLines": 0, "executableLines": 0,
            "files": [{"path": "Empty.swift", "coveredLines": 0, "executableLines": 0},
                      {"path": "Unknown.swift"}],
        })
        coverage = self.run_report()["summary"].split("#### 📊 カバレッジ", 1)[1].split("<details>", 1)[0]
        self.assertIn("**Unit** · ⚪ 計測なし", coverage)
        self.assertNotIn("**Unit** · ✅ 該当なし", coverage)

    def test_names_cannot_inject_html_tables_or_markdown(self):
        name = "evil|`[link](url)\n</details><script>&*bold*"
        self.write_report("UNIT_REPORT", "tests", [{"name": name, "result": "Passed", "seconds": 1}])
        self.write_report("UNIT_REPORT", "coverage", {
            "coveredLines": 1, "executableLines": 2,
            "files": [{"path": name + ".swift", "coveredLines": 1, "executableLines": 2}],
        })
        body = self.run_report()["summary"]
        self.assertNotIn("<script>", body)
        self.assertNotIn("evil|", body)
        self.assertNotIn("[link]", body)
        self.assertNotIn("*bold*", body)
        self.assertIn("evil&#124;&#96;&#91;link&#93;", body)
        self.assertEqual(body.count("</details>"), 2 * len(REPORTS))

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
        self.reports["UNIT_REPORT"]["omitted"] = {"files": 20, "tests": 30}
        self.assertEqual(len(self.reports), 5)  # Unit + 4 UI shards share the same comment.
        body = self.run_report()["summary"]
        self.assertLess(len(body), 60000)
        self.assertIn("文字数上限", body)
        self.assertIn("ファイル詳細 20件省略", body)
        self.assertIn("テスト詳細 30件省略", body)
        self.assertEqual(body.count("<details>"), body.count("</details>"))

    def test_wrong_run_or_attempt_outputs_are_unavailable_even_if_job_exists(self):
        for field, value in (("attempt", "1"), ("runId", "1233")):
            with self.subTest(field=field):
                report = self.reports["UNIT_REPORT"]
                previous = report[field]
                report[field] = value
                self.assertIn("| Unit | ✅ 成功 | 未取得 |", self.run_report()["summary"])
                report[field] = previous

    def test_missing_bundle_and_failed_setup_are_not_zero_tests_or_success(self):
        self.reports.clear()
        self.jobs[0]["conclusion"] = "failure"
        self.jobs[0]["steps"] = []
        result = self.run_report()
        self.assertIn("| Unit | ❌ 失敗 | 未取得 | 未取得 | 未取得 |", result["summary"])

    def test_malformed_data_and_zero_denominator_are_unavailable(self):
        self.write_report("UNIT_REPORT", "summary", {
            "passedTests": "<script>bad</script>", "failedTests": -1, "skippedTests": None,
        })
        self.write_report("UNIT_REPORT", "coverage", {
            "coveredLines": 0, "executableLines": 0,
        })
        result = self.run_report()
        self.assertIn("| Unit | ✅ 成功 | 未取得 | 未取得 | 未取得 |", result["summary"])
        self.assertNotIn("<script>", result["summary"])

    def test_invalid_json_does_not_prevent_failure_report(self):
        self.raw_reports["UNIT_REPORT"] = "{"
        self.assertIn("| Unit | ✅ 成功 | 未取得 |", self.run_report()["summary"])

    def test_null_coverage_does_not_abort_comment(self):
        self.write_report("UNIT_REPORT", "coverage", None)
        result = self.run_report()
        self.assertIn("| Unit | ⚪ 未取得 |", result["summary"])
        self.assertEqual(len(self.mutations(result)), 1)

    def test_partial_rerun_does_not_reuse_previous_attempt_data(self):
        self.jobs.pop()
        body = self.run_report()["summary"]
        self.assertIn("| UI(その他) | ⚪ 未完了・未取得 | 未取得 | 未取得 | 未取得 |", body)
        self.assertIn("| UI(その他) | 未取得 | 未取得 |", body)

    def test_shard_rerun_without_build_job_keeps_shard_results(self):
        # Re-running only failed shards reuses the earlier build, so this attempt has no build job.
        self.build_job = None
        body = self.run_report()["summary"]
        self.assertIn("| ビルド | ⚪ 未完了・未取得 | - | - | - |", body)
        self.assertIn("| ビルド | 未取得 | 未取得 |", body)
        for _, name, _ in REPORTS:
            self.assertIn(f"| {name} | ✅ 成功 | 5 | 1 | 2 |", body)
            self.assertIn(f"| {name} | 2分30秒 | 6分0秒 |", body)

    def test_build_failure_is_explicit_and_shards_are_unavailable(self):
        self.build_job["conclusion"] = "failure"
        self.build_job["steps"][0]["conclusion"] = "failure"
        self.jobs = []  # Skipped matrix jobs are not matched by their expanded names.
        for _, _, variable in REPORTS:
            self.raw_reports[variable] = ""
        body = self.run_report()["summary"]
        self.assertIn("| ビルド | ❌ 失敗 | - | - | - |", body)
        self.assertIn("| ビルド | 3分15秒 | 4分0秒 |", body)
        for _, name, _ in REPORTS:
            self.assertIn(f"| {name} | ⚪ 未完了・未取得 | 未取得 | 未取得 | 未取得 |", body)
            self.assertIn(f"| {name} | 未取得 | 未取得 |", body)

    def test_zero_percent_is_measured_when_executable_lines_exist(self):
        self.write_report("UNIT_REPORT", "coverage", {
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
                self.assertIn("iOS CI", result["summary"])

    def test_fork_only_writes_step_summary(self):
        self.context["payload"]["pull_request"]["head"]["repo"]["full_name"] = "fork/seasoning-management-iOS"
        result = self.run_report()
        self.assertEqual(self.mutations(result), [])
        self.assertIn("25.00%", result["summary"])

    def test_collection_failure_is_explicit_and_keeps_available_values(self):
        self.reports["UNIT_REPORT"]["errors"] = ["tests"]
        self.write_report("UNIT_REPORT", "tests", None)
        body = self.run_report()["summary"]
        self.assertIn("一部収集失敗", body)
        self.assertIn("**Unit** · ⚪ 未取得", body)
        self.assertIn("25.00% (25/100行)", body)

    def test_skipped_step_and_unknown_job_are_not_measured_zero_seconds(self):
        self.jobs[0]["steps"][0]["conclusion"] = "skipped"
        self.jobs.pop()
        body = self.run_report()["summary"]
        self.assertIn("| 未実施 | 6分0秒 |", body)
        self.assertIn("| UI(その他) | ⚪ 未完了・未取得 |", body)

    def test_invalid_or_negative_timestamps_are_unavailable(self):
        self.jobs[0]["completed_at"] = "invalid"
        self.jobs[1]["completed_at"] = "2026-10-10T13:00:00Z"
        body = self.run_report()["summary"]
        self.assertEqual(body.count("| 2分30秒 | 未取得 |"), 2)


SHARD = re.compile(
    r'^ {10}- name: (?P<name>.+)\n'
    r' {12}report: (?P<report>\S+)\n'
    r' {12}only: "(?P<only>[^"\n]*)"\n'
    r' {12}skip: "(?P<skip>[^"\n]*)"\n'
    r' {12}timeout: (?P<timeout>\d+)$', re.M)
NAMED_TEST = re.compile(r"SeasoningManagerUITests/(\w+)/(test\w+)")
CLASS = re.compile(r"^(?:final )?class (\w+)\b", re.M)
# A class body ends at its closing brace or the next top-level (column 0) declaration or attribute.
TOP_LEVEL_END = re.compile(
    r"^(?:\}|@|(?:(?:public|internal|private|fileprivate|open|final)\s+)*"
    r"(?:class|struct|enum|extension|protocol|actor|func|let|var|typealias)\b)", re.M)


def class_ranges(sources):
    """Map each XCTest class to its body without comment lines, so helpers outside it do not count."""
    ranges = {}
    for text in sources:
        for declaration in CLASS.finditer(text):
            end = TOP_LEVEL_END.search(text, declaration.end())
            body = text[declaration.start():end.start() if end else len(text)]
            ranges[declaration.group(1)] = "\n".join(
                line for line in body.splitlines() if not line.lstrip().startswith("//"))
    return ranges


def job_blocks(workflow):
    """Split the jobs section into {job id: text} by the two-space job keys."""
    jobs = workflow.split("\njobs:\n", 1)[1]
    keys = list(re.finditer(r"^  ([\w-]+):$", jobs, re.M))
    return {key.group(1): jobs[key.start():keys[index + 1].start() if index + 1 < len(keys) else len(jobs)]
            for index, key in enumerate(keys)}


def step_block(job, name):
    """Return the step's lines up to the next step, or None if the job has no such step."""
    lines = job.split("\n")
    header = f"      - name: {name}"
    if header not in lines:
        return None
    start = lines.index(header)
    end = next((index for index in range(start + 1, len(lines)) if lines[index].startswith("      - ")),
               len(lines))
    return "\n".join(lines[start:end])


def wiring_errors(workflow):
    """Names the reporter looks up and the matrix values passed to the scripts must exist."""
    errors = []
    jobs = job_blocks(workflow)
    js_jobs = set(re.findall(r"job\.name === '([^']+)'", workflow))
    js_steps = set(re.findall(r"step\.name === '([^']+)'", workflow))
    if len(js_jobs) != 1 or len(js_steps) != 2 or "Run tests" not in js_steps:
        errors.append(f"Reporter must look up one build job, its step, and Run tests: {js_jobs} {js_steps}")
    build = jobs.get("build", "")
    build_name = re.search(r"^ {4}name: (.+)$", build, re.M)
    if build_name is None or build_name.group(1) not in js_jobs:
        errors.append("Build job name does not match the reporter")
    if not all(step_block(build, step) for step in js_steps - {"Run tests"}):
        errors.append("Build step name does not match the reporter")
    tests = jobs.get("tests", "")
    if not re.search(r"^ {4}name: \$\{\{ matrix\.name \}\}$", tests, re.M):
        errors.append("Test job name is not the matrix name")
    run = step_block(tests, "Run tests")
    if run is None:
        errors.append("Test job has no Run tests step")
        run = ""
    for required in ("HARNESS_XCODE_ACTION: test-without-building", "HARNESS_SKIP_TESTING: ${{ matrix.skip }}",
                     "TEST_ONLY: ${{ matrix.only }}", 'bash harness/test-ios.sh "$TEST_ONLY" '):
        if required not in run:
            errors.append(f"Run tests step does not pass: {required}")
    return errors


def shard_configuration(workflow, sources):
    """Read the matrix with regular expressions and return (errors, shards, named tests)."""
    errors = wiring_errors(workflow)
    shards = [match.groupdict() for match in SHARD.finditer(workflow)]
    # Count fields anywhere (block or flow style, any indentation) so unparsed entries cannot hide.
    counts = [len(re.findall(r"^ {10}- name: ", workflow, re.M)),
              len(re.findall(r"(?<![\w.-])report:[ \t]", workflow)),
              len(re.findall(r"(?<![\w.-])only:[ \t]", workflow))]
    if any(count != len(shards) for count in counts):
        errors.append(f"Matrix entry without name/report/only/skip/timeout in order: {counts} vs {len(shards)}")
    keys = [shard["report"] for shard in shards]
    if len(set(keys)) != len(keys) or not all(re.fullmatch(r"[a-z][a-z0-9_]*_report", key) for key in keys):
        errors.append(f"Invalid or duplicate report keys: {keys}")
    outputs = re.findall(r"^ {6}(\w+): \$\{\{ steps\.collect\.outputs\.(\w+) \}\}$", workflow, re.M)
    if any(key != value for key, value in outputs) or sorted(key for key, _ in outputs) != sorted(keys):
        errors.append(f"tests.outputs do not match matrix reports: {outputs}")
    env = re.findall(r"^ {10}(\w+_REPORT): \$\{\{ needs\.tests\.outputs\.(\w+) \}\}$", workflow, re.M)
    if any(variable != key.upper() for variable, key in env) or sorted(key for _, key in env) != sorted(keys):
        errors.append(f"Report env does not match matrix reports: {env}")
    rows = re.findall(r"^ {14}\['([^']+)', '[^']+', '(\w+_REPORT)'\],?$", workflow, re.M)
    if sorted(rows) != sorted((shard["name"], shard["report"].upper()) for shard in shards):
        errors.append(f"Reporter rows do not match matrix jobs: {rows}")
    if "HARNESS_REPORT_KEY: ${{ matrix.report }}" not in workflow:
        errors.append("Collect step does not pass the matrix report key")

    units = [shard for shard in shards if "SeasoningManagerTests" in shard["only"] + shard["skip"]]
    if [(shard["only"], shard["skip"]) for shard in units] != [("SeasoningManagerTests", "")]:
        errors.append(f"Unit tests must run in exactly one shard without skips: {units}")
    rest = [shard for shard in shards if shard["only"] == "SeasoningManagerUITests"]
    named_shards = [shard for shard in shards if shard not in units and shard not in rest]
    if len(rest) != 1:
        errors.append(f"Expected exactly one complement UI shard, found {len(rest)}")

    classes = class_ranges(sources)
    named = []
    for shard in named_shards:
        if shard["skip"]:
            errors.append(f"Named shard must not skip tests: {shard['name']}")
        for identifier in shard["only"].split(","):
            match = NAMED_TEST.fullmatch(identifier)
            if match is None:
                errors.append(f"Not a UI test identifier: {identifier!r}")
                continue
            body = classes.get(match.group(1), "")
            if re.search(rf"\bfunc {match.group(2)}\(", body) is None:
                errors.append(f"Test not found in class: {identifier}")
            named.append(identifier)
    if len(set(named)) != len(named):
        errors.append(f"Duplicate named tests: {sorted({item for item in named if named.count(item) > 1})}")
    if len(rest) == 1:
        skipped = rest[0]["skip"].split(",") if rest[0]["skip"] else []
        if len(set(skipped)) != len(skipped) or set(skipped) != set(named):
            errors.append("Complement shard must skip exactly the named tests")
    return errors, shards, named


class WorkflowShardTests(unittest.TestCase):
    def setUp(self):
        self.workflow = WORKFLOW.read_text(encoding="utf-8")
        self.sources = [path.read_text(encoding="utf-8") for path in sorted(UI_SOURCES.glob("*.swift"))]

    def errors(self, workflow, sources=None):
        return shard_configuration(workflow, self.sources if sources is None else sources)[0]

    def assert_rejected(self, expected, workflow, sources=None):
        self.assertNotEqual((workflow, sources), (self.workflow, None))
        errors = self.errors(workflow, sources)
        self.assertTrue(any(error.startswith(expected) for error in errors), errors)

    def edit_shard(self, name, field, value):
        lines = self.workflow.split("\n")
        start = lines.index(f"          - name: {name}")
        offset = {"report": 1, "only": 2, "skip": 3}[field]
        lines[start + offset] = f"            {field}: {value}"
        return "\n".join(lines)

    def test_matrix_outputs_reporter_and_sources_agree(self):
        errors, shards, named = shard_configuration(self.workflow, self.sources)
        self.assertEqual(errors, [])
        self.assertEqual(len(shards), 5)
        self.assertEqual(len(named), 11)
        self.assertEqual([shard["name"] for shard in shards], [name for name, _, _ in REPORTS])
        self.assertEqual([shard["report"].upper() for shard in shards], [variable for _, _, variable in REPORTS])

    def test_inconsistent_shards_are_rejected(self):
        moved = "SeasoningManagerProductUITests/testProductRegistrationSavesAndSurvivesRelaunch"
        first = "SeasoningManagerUITests/SeasoningManagerProductUITests/testOptionalEditingCancelAndClearLastNutrient"
        product_2 = re.search(r'^ {12}only: "(SeasoningManagerUITests/SeasoningManagerProductUITests/testOptionalInputs[^"]*)"$',
                              self.workflow, re.M).group(1)
        rest_skip = re.search(r'^ {12}skip: "(.+)"$', self.workflow, re.M).group(1)
        cases = {
            "Test not found in class": self.workflow.replace(
                "testProductRegistrationSavesAndSurvivesRelaunch", "testMissingFromSource"),
            "Test not found in class: SeasoningManagerUITests/SeasoningManagerInventoryUITests": self.workflow.replace(
                moved, moved.replace("SeasoningManagerProductUITests", "SeasoningManagerInventoryUITests")),
            "Duplicate named tests": self.edit_shard("UI tests (商品2)", "only", f'"{first},{product_2}"'),
            "Complement shard must skip exactly": self.edit_shard(
                "UI tests (その他)", "skip", '"' + rest_skip.rsplit(",", 1)[0] + '"'),
            "Unit tests must run in exactly one shard": self.edit_shard(
                "Unit tests", "skip", '"SeasoningManagerTests/SeasoningSuite"'),
            "Matrix entry without": self.edit_shard("Unit tests", "skip", ""),
            "tests.outputs do not match": self.workflow.replace(
                "outputs.ui_rest_report }}\n    strategy", "outputs.ui_other_report }}\n    strategy"),
            "Report env does not match": self.workflow.replace(
                "          UI_REST_REPORT: ${{ needs.tests.outputs.ui_rest_report }}\n", ""),
            "Reporter rows do not match": self.workflow.replace(
                "              ['UI tests (その他)', 'UI(その他)', 'UI_REST_REPORT']\n", ""),
            "Invalid or duplicate report keys": self.edit_shard("UI tests (その他)", "report", "unit_report"),
            "Named shard must not skip tests": self.edit_shard(
                "UI tests (商品1)", "skip", '"SeasoningManagerUITests/SeasoningManagerProductUITests/testLater"'),
            "Not a UI test identifier": self.edit_shard(
                "UI tests (商品1)", "only", '"SeasoningManagerUITests/SeasoningManagerProductUITests"'),
            "Expected exactly one complement UI shard": self.edit_shard(
                "UI tests (在庫1)", "only", '"SeasoningManagerUITests"'),
            "Collect step does not pass the matrix report key": self.workflow.replace(
                "HARNESS_REPORT_KEY: ${{ matrix.report }}", "HARNESS_REPORT_KEY: unit_report"),
        }
        for expected, workflow in cases.items():
            with self.subTest(expected=expected):
                self.assert_rejected(expected, workflow)

    def test_hidden_matrix_entries_are_rejected(self):
        lines = self.workflow.split("\n")
        start = lines.index("          - name: Unit tests")
        entry = lines[start:start + 5]
        cases = {
            "deeper indentation": "\n".join(["  " + line for line in entry]),
            "flow mapping": '          - { name: Unit tests, report: unit_report, only: "SeasoningManagerTests", '
                            'skip: "", timeout: 15 }',
        }
        for name, replacement in cases.items():
            with self.subTest(name):
                workflow = "\n".join(lines[:start] + [replacement] + lines[start + 5:])
                self.assert_rejected("Matrix entry without", workflow)

    def test_reporter_lookups_and_matrix_wiring_must_exist(self):
        cases = {
            "Run tests step does not pass: HARNESS_SKIP_TESTING": self.workflow.replace(
                "HARNESS_SKIP_TESTING: ${{ matrix.skip }}", "HARNESS_SKIP_TESTING: \"\""),
            "Run tests step does not pass: TEST_ONLY": self.workflow.replace(
                "TEST_ONLY: ${{ matrix.only }}", "TEST_ONLY: SeasoningManagerUITests"),
            "Run tests step does not pass: bash harness/test-ios.sh": self.workflow.replace(
                'bash harness/test-ios.sh "$TEST_ONLY" ', 'bash harness/test-ios.sh all '),
            "Test job name is not the matrix name": self.workflow.replace(
                "    name: ${{ matrix.name }}", "    name: iOS ${{ matrix.name }}"),
            "Build job name does not match": self.workflow.replace(
                "    name: Build for testing\n", "    name: Build\n"),
            "Build step name does not match": self.workflow.replace(
                "      - name: Build for testing\n", "      - name: Build\n"),
            "Test job has no Run tests step": self.workflow.replace(
                "      - name: Run tests\n", "      - name: Test\n"),
            "Reporter must look up": self.workflow.replace(
                "step.name === 'Run tests'", "step.name === 'Test'"),
        }
        for expected, workflow in cases.items():
            with self.subTest(expected=expected):
                self.assert_rejected(expected, workflow)

    def test_test_functions_outside_the_class_body_do_not_count(self):
        product = "final class SeasoningManagerProductUITests: XCTestCase {\n"
        cases = {
            # Helpers live in a top-level extension after the last class; it is not that class.
            "testOnlyInHelperExtension": [source + "\n@MainActor\nextension XCTestCase {\n"
                                          "    func testOnlyInHelperExtension() throws {}\n}\n"
                                          for source in self.sources],
            "testOnlyInComment": [source.replace(product, product + "    // func testOnlyInComment() throws {}\n")
                                  for source in self.sources],
        }
        for name, sources in cases.items():
            with self.subTest(name):
                self.assertNotEqual(sources, self.sources)
                workflow = self.workflow.replace("testProductRegistrationSavesAndSurvivesRelaunch", name)
                self.assert_rejected("Test not found in class: SeasoningManagerUITests/"
                                     f"SeasoningManagerProductUITests/{name}", workflow, sources)
                # The same name inside the class body is accepted.
                inside = [source.replace(product, product + f"    func {name}() throws {{}}\n")
                          for source in self.sources]
                self.assertEqual(self.errors(workflow, inside), [])


if __name__ == "__main__":
    unittest.main()
