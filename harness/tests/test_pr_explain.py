"""PR の地図・解説の検査・公開境界を、実入力とローカル Git で確かめる。"""

import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / ".github/scripts"
ENV = {**os.environ, "PYTHONDONTWRITEBYTECODE": "1"}
for name in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
    ENV.pop(name, None)
SPEC = importlib.util.spec_from_file_location("pr_change_map", SCRIPTS / "build-pr-change-map.py")
MAP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MAP)
APP = "src/SeasoningManager/SeasoningManager"
UNIT = "src/SeasoningManager/SeasoningManagerTests"
UI = "src/SeasoningManager/SeasoningManagerUITests"


def run(*args, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, env=ENV, text=True, capture_output=True)


class SwiftTestDeclarations(unittest.TestCase):
    def test_testing_labels_function_names_and_multiline_arguments(self):
        source = '''
        @Test("空の名前は失敗する") func rejectsEmptyName() {}
        @Test(arguments: ["しょうゆ", "みそ"])
        func acceptsName(name: String) {}
        @Test(
            "空白を取り除く",
            arguments: [
                "  しょうゆ", "みそ  ",
            ]
        )
        @MainActor
        func trimsName(name: String) {}
        @Test func failureKeepsDraft() async throws {}
        '''
        self.assertEqual(MAP.test_names(source), {"空の名前は失敗する", "acceptsName", "空白を取り除く", "failureKeepsDraft"})

    def test_comments_nested_comments_and_strings_do_not_create_declarations(self):
        source = '''
        // @Test("行コメント") func fakeLine() {}
        /* @Test func fakeBlock() {} /* nested */ */
        let a = "@Test func fakeString() {}"
        let b = #"@Test func fakeRaw() {}"#
        let c = """
        @Test func fakeMultiline() {}
        """
        let d = ##"""
        @Test func fakeRawMultiline() {}
        """##
        @Test("括弧 ) と引用符 \\" を含む")
        func real() {}
        '''
        self.assertEqual(MAP.test_names(source), {'括弧 ) と引用符 \\" を含む'})

    def test_interpolated_strings_with_nested_quotes_do_not_create_declarations(self):
        source = r'''
        let text = "\(String("@Test func ghost() {}"))"
        let raw = #"\#(String("@Test func rawGhost() {}"))"#
        let nested = "\(String("\(String("@Test func nestedGhost() {}"))"))"
        @Test func real() {}
        '''
        self.assertEqual(MAP.test_names(source), {"real"})

    def test_xctest_and_python_unittest_names_ignore_fake_strings(self):
        self.assertEqual(MAP.test_names('func testLaunch() {}\n// func testComment() {}\nlet s = "func testString() {}"', UI + "/LaunchTests.swift"), {"testLaunch"})
        source = 'class Cases:\n    def test_success(self): pass\n    async def test_failure(self): pass\n    sample = "def test_fake(): pass"\n'
        self.assertEqual(MAP.test_names(source, "harness/tests/test_case.py"), {"test_success", "test_failure"})
        self.assertEqual(MAP.test_names("not python (", "harness/tests/test_case.py"), set())

    def test_rename_and_body_edit_do_not_report_unchanged_declarations(self):
        old = UNIT + "/OldTests.swift"
        new = UNIT + "/NewTests.swift"
        before = {old: '@Test("同じ名前") func old() {}\n@Test func removed() {}'}
        after = {new: '@Test("同じ名前") func renamed() { print("変更") }\n@Test func added() {}'}
        changes = MAP.test_changes([{"path": new, "oldPath": old}], before, after)
        self.assertEqual(changes, {"added": [{"file": new, "name": "added"}], "removed": [{"file": new, "name": "removed"}], "files": [new]})
        renamed_only = MAP.test_changes([{"path": new, "oldPath": old}], before, {new: before[old]})
        self.assertEqual(renamed_only["added"], [])
        self.assertEqual(renamed_only["removed"], [])

    def test_groups_match_actual_app_structure_and_legacy_is_separate(self):
        samples = {
            APP + "/Models/Product.swift": "Models",
            APP + "/Item.swift": "Models",
            APP + "/Domain/Registration.swift": "Domain",
            APP + "/Data/ItemActions.swift": "Data",
            APP + "/ContentView.swift": "画面・起動",
            APP + "/SeasoningManagerApp.swift": "画面・起動",
            APP + "/Views/AddView.swift": "画面・起動",
            APP + "/Other.swift": "アプリ(その他)",
            APP + "/Info.plist": "Xcode 設定",
            APP + "/Assets.xcassets/Contents.json": "Xcode 設定",
            UNIT + "/ItemTests.swift": "単体テスト",
            UI + "/LaunchTests.swift": "UI テスト",
            "src/SeasoningManager/SeasoningManager.xcodeproj/project.pbxproj": "Xcode 設定",
            "docs/seasoning-management/index.md": "docs",
            "harness/tests/test_pr_explain.py": "ハーネス",
            "old/Item.swift": "旧コード",
        }
        for path, label in samples.items():
            with self.subTest(path=path):
                self.assertEqual(MAP.layer_of(path)[1], label)

    def test_targets_only_when_filename_is_unambiguous_and_import_is_not_file_edge(self):
        target = APP + "/Data/ItemActions.swift"
        test = UNIT + "/ItemActionsTests.swift"
        self.assertEqual(MAP.target_of(test, frozenset({target, test})), target)
        self.assertIsNone(MAP.target_of(test, frozenset({target, APP + "/Domain/ItemActions.swift", test})))
        self.assertIsNone(MAP.target_of(UNIT + "/FeatureTests.swift", frozenset({target})))
        self.assertEqual(MAP.edges_in({target: "import SwiftData\nimport SeasoningManager", APP + "/SwiftData.swift": "struct Data {}"}), set())


class MapGitBoundary(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.repo = Path(self.workspace.name)
        self.git("init", "--quiet", "-b", "master")
        self.git("config", "user.name", "cases")
        self.git("config", "user.email", "cases@example.com")

    def git(self, *args):
        result = run("git", *args, cwd=self.repo)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def write(self, path, text):
        file = self.repo / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text, encoding="utf-8")

    def commit(self, message):
        self.git("add", "-A")
        self.git("commit", "--quiet", "-m", message)
        return self.git("rev-parse", "HEAD")

    def build(self, base, head):
        return run("python3", str(SCRIPTS / "build-pr-change-map.py"), "--base", base, "--head", head, "--pr", "123", "--head-branch", "topic", "--base-branch", "master", cwd=self.repo)

    def test_real_git_rename_diff_and_untrusted_sources_are_never_executed(self):
        old, new = UNIT + "/ItemTests.swift", UNIT + "/RenamedTests.swift"
        self.write(APP + "/Item.swift", "struct Item {}\n")
        self.write(old, '@Test("名前の保持") func keepsName() {}\n')
        base = self.commit("before")
        (self.repo / old).rename(self.repo / new)
        self.write("harness/tests/test_payload.py", "from pathlib import Path\nPath('executed').touch()\nclass Payload:\n    def test_inert(self): pass\n")
        head = self.commit("rename and add inert test")
        result = self.build(base, head)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["tests"]["added"], [{"file": "harness/tests/test_payload.py", "name": "test_inert"}])
        self.assertEqual(data["tests"]["removed"], [])
        file = next(file for group in data["groups"] for file in group["files"] if file["path"] == new)
        self.assertEqual(file["oldPath"], old)
        self.assertEqual(file["status"], "R")
        self.assertEqual(len(data["commits"]), 1)
        self.assertFalse((self.repo / "executed").exists())
        self.assertEqual(self.build("no-such-ref", head).returncode, 1)


class PrExplainRegressionCases(unittest.TestCase):
    def check_cases(self, name):
        result = run("bash", str(SCRIPTS / name))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("NG ", result.stdout)
        self.assertIn("ok ", result.stdout)

    def test_validator_accepts_example_and_rejects_invalid_shape_refs_and_excerpts(self):
        self.check_cases("build-pr-explain-cases.sh")

    def test_template_rejects_dangerous_html_apis_and_external_csp_sources(self):
        self.check_cases("check-pr-explain-template-cases.sh")

    @unittest.skipUnless(shutil.which("node"), "Node.js がないため renderer core は未実施")
    def test_renderer_core_matches_validator_and_all_five_screens(self):
        self.check_cases("pr-explain-core-cases.sh")

    def test_bare_remote_publish_update_delete_preserves_other_prs_and_retries(self):
        self.check_cases("pr-explain-pages-cases.sh")

    def test_local_build_has_checked_explanation_and_rejects_repository_output(self):
        with tempfile.TemporaryDirectory() as work:
            work = Path(work)
            sha = run("git", "rev-parse", "HEAD").stdout.strip()
            explanation = {"version": 1, "pr": 123, "sha": sha, "overview": {"title": "題", "lead": "要約", "before": [], "after": [{"text": "後"}]}}
            source = work / "input.json"
            source.write_text(json.dumps(explanation), encoding="utf-8")
            output = work / "html"
            command = ["python3", str(SCRIPTS / "build-pr-explain-local.py"), "--base", "HEAD~1", "--head", "HEAD", "--pr", "123", "--head-branch", "topic", "--base-branch", "master", "--out", str(output)]
            result = run(*command, "--explain", str(source))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual({file.name for file in output.iterdir()}, {"index.html", "explain.json", "change-map.json"})
            self.assertEqual(json.loads((output / "explain.json").read_text())["sha"], sha)
            self.assertEqual(run(*command).returncode, 0)
            self.assertFalse((output / "explain.json").exists())
            self.assertEqual(run(*command[:-1], str(ROOT / "generated")).returncode, 2)
            explanation["unknown"] = True
            source.write_text(json.dumps(explanation), encoding="utf-8")
            (output / "index.html").write_text("unchanged", encoding="utf-8")
            self.assertEqual(run(*command, "--explain", str(source)).returncode, 1)
            self.assertEqual((output / "index.html").read_text(), "unchanged")


if __name__ == "__main__":
    unittest.main()
