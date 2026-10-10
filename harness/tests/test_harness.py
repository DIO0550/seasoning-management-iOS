"""Regression cases for configuration failures and the iOS command boundary."""

import importlib.util
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("harness_check", ROOT / "harness/check.py")
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class HarnessConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        for name in ("AGENTS.md", "CLAUDE.md"):
            shutil.copyfile(ROOT / name, self.root / name)
        for name in ("rules", "harness", ".claude", "docs"):
            shutil.copytree(ROOT / name, self.root / name, ignore=shutil.ignore_patterns("__pycache__"))

    def test_current_configuration_is_valid(self):
        self.assertEqual(CHECK.check(self.root), [])

    def test_missing_rule_blocks_validation(self):
        (self.root / "rules/swift.md").unlink()
        errors = CHECK.check(self.root)
        self.assertTrue(any("Missing: rules/swift.md" in error for error in errors))

    def test_broken_skill_reference_blocks_validation(self):
        path = self.root / ".claude/skills/implementation-flow/SKILL.md"
        with path.open("a", encoding="utf-8") as stream:
            stream.write("\n[missing](missing.md)\n")
        self.assertTrue(any("Broken reference" in error for error in CHECK.check(self.root)))

    def test_misnamed_skill_blocks_validation(self):
        path = self.root / ".claude/skills/harness-record/SKILL.md"
        source = path.read_text(encoding="utf-8")
        path.write_text(source.replace("name: harness-record", "name: wrong-name"), encoding="utf-8")
        self.assertTrue(any("Invalid name" in error for error in CHECK.check(self.root)))

    def test_missing_hook_script_blocks_validation(self):
        (self.root / ".claude/hooks/post-edit-check.sh").unlink()
        self.assertTrue(any("Missing hook script" in error for error in CHECK.check(self.root)))

    def test_empty_hook_blocks_validation(self):
        path = self.root / ".claude/settings.json"
        path.write_text(json.dumps({"hooks": {"PostToolUse": []}}), encoding="utf-8")
        self.assertIn("PostToolUse hook is empty", CHECK.check(self.root))

    def test_invalid_settings_blocks_validation(self):
        (self.root / ".claude/settings.json").write_text("{", encoding="utf-8")
        self.assertTrue(any("Invalid Claude settings" in error for error in CHECK.check(self.root)))

    def test_rule_budget_blocks_validation(self):
        with (self.root / "rules/swift.md").open("a", encoding="utf-8") as stream:
            stream.write("\n" * CHECK.ALWAYS_LOADED_CAP)
        self.assertTrue(any("Always-loaded rules" in error for error in CHECK.check(self.root)))

    def test_post_edit_hook_returns_feedback_for_broken_configuration(self):
        (self.root / "rules/swift.md").unlink()
        result = subprocess.run(
            ["bash", str(self.root / ".claude/hooks/post-edit-check.sh")],
            input=json.dumps({"tool_name": "Edit"}),
            text=True,
            capture_output=True,
            cwd=self.workspace.name,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("Missing: rules/swift.md", result.stderr)


class IOSTestCommandTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.bin_dir = Path(self.workspace.name)
        self.args_file = self.bin_dir / "arguments.json"
        fake_xcodebuild = self.bin_dir / "xcodebuild"
        fake_xcodebuild.write_text(
            "#!" + shutil.which("python3") + "\n"
            "import json, os, pathlib, sys\n"
            "pathlib.Path(os.environ['HARNESS_TEST_ARGS']).write_text("
            "json.dumps({'args': sys.argv[1:], 'cwd': os.getcwd()}))\n"
            "sys.exit(int(os.environ.get('HARNESS_TEST_EXIT', '0')))\n",
            encoding="utf-8",
        )
        fake_xcodebuild.chmod(0o755)
        self.env = dict(os.environ)
        self.env["PATH"] = str(self.bin_dir) + os.pathsep + self.env["PATH"]
        self.env["HARNESS_TEST_ARGS"] = str(self.args_file)

    def run_script(self, *args):
        return subprocess.run(
            [shutil.which("bash"), str(ROOT / "harness/test-ios.sh"), *args],
            cwd=self.workspace.name,
            env=self.env,
            text=True,
            capture_output=True,
        )

    def test_both_targets_keep_destination_as_one_argument(self):
        destination = "platform=iOS Simulator,name=iPhone test"
        for target in ("SeasoningManagerTests", "SeasoningManagerUITests"):
            with self.subTest(target=target):
                result = self.run_script(target, destination)
                self.assertEqual(result.returncode, 0, result.stderr)
                invocation = json.loads(self.args_file.read_text())
                args = invocation["args"]
                self.assertEqual(args[0], "test")
                self.assertEqual(args[args.index("-destination") + 1], destination)
                self.assertIn("-only-testing:" + target, args)
                self.assertIn("CODE_SIGNING_ALLOWED=NO", args)
                self.assertEqual(invocation["cwd"], str(ROOT))

    def test_all_runs_without_target_filter(self):
        result = self.run_script("all", "platform=iOS Simulator,id=test")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.args_file.read_text())["args"]
        self.assertFalse(any(arg.startswith("-only-testing:") for arg in args))
        self.assertNotIn("-resultBundlePath", args)
        self.assertNotIn("-enableCodeCoverage", args)

    def test_result_bundle_enables_coverage_and_keeps_path_as_one_argument(self):
        path = str(self.bin_dir / "results with spaces.xcresult")
        self.env["HARNESS_RESULT_BUNDLE"] = path
        result = self.run_script("SeasoningManagerTests", "platform=iOS Simulator,id=test")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = json.loads(self.args_file.read_text())["args"]
        self.assertEqual(args[args.index("-resultBundlePath") + 1], path)
        self.assertEqual(args[args.index("-enableCodeCoverage") + 1], "YES")

    def test_xcode_failure_is_propagated(self):
        self.env["HARNESS_TEST_EXIT"] = "65"
        self.assertEqual(self.run_script("all", "platform=iOS Simulator,id=test").returncode, 65)

    def test_invalid_requests_do_not_launch_xcode(self):
        for args in ((), ("unknown", "destination"), ("all", "")):
            with self.subTest(args=args):
                self.assertEqual(self.run_script(*args).returncode, 2)
                self.assertFalse(self.args_file.exists())

    def test_missing_xcode_is_not_success(self):
        # The empty directory also makes this deterministic on Macs with Xcode.
        self.env["PATH"] = str(self.bin_dir / "empty")
        result = self.run_script("all", "platform=iOS Simulator,id=test")
        self.assertEqual(result.returncode, 2)
        self.assertIn("iOS tests not run", result.stderr)
        self.assertFalse(self.args_file.exists())


if __name__ == "__main__":
    unittest.main()
