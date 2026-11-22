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
        for name in ("rules", "harness", ".claude", ".github", "docs"):
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

    def test_missing_new_agent_blocks_validation(self):
        for name in ("planner", "implementer"):
            with self.subTest(agent=name):
                path = self.root / ".claude/agents" / f"{name}.md"
                source = path.read_text(encoding="utf-8")
                path.unlink()
                self.assertIn(f"Missing: .claude/agents/{name}.md", CHECK.check(self.root))
                path.write_text(source, encoding="utf-8")

    def test_invalid_new_agent_metadata_blocks_validation(self):
        for name in ("planner", "implementer"):
            path = self.root / ".claude/agents" / f"{name}.md"
            source = path.read_text(encoding="utf-8")
            for malformed, expected in (
                ("# Missing metadata\n", "Missing frontmatter"),
                (source.replace(f"name: {name}", "name: wrong-name"), "Invalid name"),
                (source.replace("description:", "omitted-description:"), "Missing description"),
            ):
                with self.subTest(agent=name, failure=expected):
                    path.write_text(malformed, encoding="utf-8")
                    self.assertIn(f"{expected}: .claude/agents/{name}.md", CHECK.check(self.root))
                    path.write_text(source, encoding="utf-8")

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
        # Variables from the caller's shell (e.g. HARNESS_SKIP_TESTING) must not change the command.
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("HARNESS_")}
        self.env["PATH"] = str(self.bin_dir) + os.pathsep + self.env["PATH"]
        self.env["HARNESS_TEST_ARGS"] = str(self.args_file)

    def run_script(self, *args, bash=None):
        return subprocess.run(
            [bash or shutil.which("bash"), str(ROOT / "harness/test-ios.sh"), *args],
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

    def args(self):
        return json.loads(self.args_file.read_text())["args"]

    def xctestrun(self):
        path = self.bin_dir / "Products with spaces" / "SeasoningManager_iphonesimulator.xctestrun"
        path.parent.mkdir(exist_ok=True)
        path.write_text("<plist/>", encoding="utf-8")
        return path

    def test_default_command_is_unchanged_without_new_variables(self):
        destination = "platform=iOS Simulator,id=test"
        self.assertEqual(self.run_script("SeasoningManagerUITests", destination).returncode, 0)
        self.assertEqual(self.args(), [
            "test", "-project", "src/SeasoningManager/SeasoningManager.xcodeproj",
            "-scheme", "SeasoningManager", "-configuration", "Debug",
            "-destination", destination, "-destination-timeout", "120",
            "-retry-tests-on-failure", "CODE_SIGNING_ALLOWED=NO",
            "-parallel-testing-enabled", "YES", "-parallel-testing-worker-count", "2",
            "-only-testing:SeasoningManagerUITests",
        ])

    def test_comma_separated_targets_and_skips_become_separate_filters(self):
        self.env["HARNESS_SKIP_TESTING"] = "SeasoningManagerUITests/A/testOne,SeasoningManagerUITests/B"
        result = self.run_script("SeasoningManagerTests,SeasoningManagerUITests/A",
                                 "platform=iOS Simulator,id=test")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.args()
        self.assertEqual([arg for arg in args if arg.startswith("-only-testing:")],
                         ["-only-testing:SeasoningManagerTests", "-only-testing:SeasoningManagerUITests/A"])
        self.assertEqual([arg for arg in args if arg.startswith("-skip-testing:")],
                         ["-skip-testing:SeasoningManagerUITests/A/testOne",
                          "-skip-testing:SeasoningManagerUITests/B"])

    def test_build_for_testing_builds_once_without_test_options(self):
        derived = str(self.bin_dir / "Derived Data")
        self.env.update(HARNESS_XCODE_ACTION="build-for-testing", HARNESS_DERIVED_DATA=derived,
                        HARNESS_PARALLEL_TESTS="NO")
        destination = "platform=iOS Simulator,id=test"
        result = self.run_script("all", destination)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.args(), [
            "build-for-testing", "-project", "src/SeasoningManager/SeasoningManager.xcodeproj",
            "-scheme", "SeasoningManager", "-configuration", "Debug",
            "-destination", destination, "-destination-timeout", "120",
            "-derivedDataPath", derived, "-enableCodeCoverage", "YES", "CODE_SIGNING_ALLOWED=NO",
        ])
        self.assertEqual(json.loads(self.args_file.read_text())["cwd"], str(ROOT))

    def test_test_without_building_uses_only_the_xctestrun(self):
        xctestrun = self.xctestrun()
        bundle = str(self.bin_dir / "shard results.xcresult")
        self.env.update(HARNESS_XCODE_ACTION="test-without-building", HARNESS_XCTESTRUN=str(xctestrun),
                        HARNESS_PARALLEL_TESTS="NO", HARNESS_RESULT_BUNDLE=bundle,
                        HARNESS_SKIP_TESTING="SeasoningManagerUITests/A/testOne")
        destination = "platform=iOS Simulator,id=test"
        result = self.run_script("SeasoningManagerUITests", destination)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.args(), [
            "test-without-building", "-xctestrun", str(xctestrun),
            "-destination", destination, "-destination-timeout", "120", "-retry-tests-on-failure",
            "-parallel-testing-enabled", "NO",
            "-only-testing:SeasoningManagerUITests", "-skip-testing:SeasoningManagerUITests/A/testOne",
            "-resultBundlePath", bundle, "-enableCodeCoverage", "YES",
        ])

    def test_relative_xctestrun_is_resolved_from_the_caller(self):
        xctestrun = self.xctestrun()
        self.env.update(HARNESS_XCODE_ACTION="test-without-building",
                        HARNESS_XCTESTRUN=str(xctestrun.relative_to(self.bin_dir)))
        result = self.run_script("all", "platform=iOS Simulator,id=test")
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.args()
        self.assertEqual(Path(args[args.index("-xctestrun") + 1]).resolve(), xctestrun.resolve())

    def test_invalid_mode_requests_do_not_launch_xcode(self):
        xctestrun = str(self.xctestrun())
        derived = str(self.bin_dir / "DerivedData")
        cases = {
            "unknown action": ({"HARNESS_XCODE_ACTION": "build"}, "all"),
            "all with another target": ({}, "all,SeasoningManagerTests"),
            "empty target element": ({}, "SeasoningManagerTests,"),
            "leading empty element": ({}, ",SeasoningManagerTests"),
            "unknown target element": ({}, "SeasoningManagerTests,Other"),
            "skip whole target": ({"HARNESS_SKIP_TESTING": "SeasoningManagerTests"}, "all"),
            "skip unknown target": ({"HARNESS_SKIP_TESTING": "Other/Test"}, "all"),
            "skip empty element": ({"HARNESS_SKIP_TESTING": "SeasoningManagerUITests/A,"}, "all"),
            "derived data in test": ({"HARNESS_DERIVED_DATA": derived}, "all"),
            "xctestrun in test": ({"HARNESS_XCTESTRUN": xctestrun}, "all"),
            "build subset": ({"HARNESS_XCODE_ACTION": "build-for-testing",
                              "HARNESS_DERIVED_DATA": derived}, "SeasoningManagerTests"),
            "build without derived data": ({"HARNESS_XCODE_ACTION": "build-for-testing"}, "all"),
            "build with skip": ({"HARNESS_XCODE_ACTION": "build-for-testing", "HARNESS_DERIVED_DATA": derived,
                                 "HARNESS_SKIP_TESTING": "SeasoningManagerUITests/A"}, "all"),
            "build with result bundle": ({"HARNESS_XCODE_ACTION": "build-for-testing",
                                          "HARNESS_DERIVED_DATA": derived,
                                          "HARNESS_RESULT_BUNDLE": str(self.bin_dir / "r.xcresult")}, "all"),
            "build with xctestrun": ({"HARNESS_XCODE_ACTION": "build-for-testing", "HARNESS_DERIVED_DATA": derived,
                                      "HARNESS_XCTESTRUN": xctestrun}, "all"),
            "run without xctestrun": ({"HARNESS_XCODE_ACTION": "test-without-building"}, "all"),
            "run with missing xctestrun": ({"HARNESS_XCODE_ACTION": "test-without-building",
                                            "HARNESS_XCTESTRUN": str(self.bin_dir / "missing.xctestrun")}, "all"),
            "run with directory": ({"HARNESS_XCODE_ACTION": "test-without-building",
                                    "HARNESS_XCTESTRUN": str(self.bin_dir)}, "all"),
            "run with derived data": ({"HARNESS_XCODE_ACTION": "test-without-building",
                                       "HARNESS_XCTESTRUN": xctestrun, "HARNESS_DERIVED_DATA": derived}, "all"),
        }
        base = dict(self.env)
        for name, (variables, target) in cases.items():
            with self.subTest(name):
                self.env = dict(base, **variables)
                result = self.run_script(target, "platform=iOS Simulator,id=test")
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn("Usage:", result.stderr)
                self.assertFalse(self.args_file.exists())

    def test_runs_without_filters_on_every_available_bash(self):
        # macOS ships bash 3.2, where expanding an empty array under set -u is an error.
        shells = [shutil.which("bash")]
        if Path("/bin/bash").exists():
            version = subprocess.run(["/bin/bash", "-c", "echo ${BASH_VERSINFO[0]}"],
                                     capture_output=True, text=True).stdout.strip()
            if version == "3" and "/bin/bash" not in shells:
                shells.append("/bin/bash")
        xctestrun = str(self.xctestrun())
        cases = {
            "test all": {},
            "test-without-building all": {"HARNESS_XCODE_ACTION": "test-without-building",
                                          "HARNESS_XCTESTRUN": xctestrun},
            "build-for-testing all": {"HARNESS_XCODE_ACTION": "build-for-testing",
                                      "HARNESS_DERIVED_DATA": str(self.bin_dir / "DerivedData")},
        }
        base = dict(self.env)
        for shell in shells:
            for name, variables in cases.items():
                with self.subTest(shell=shell, case=name):
                    self.args_file.unlink(missing_ok=True)
                    self.env = dict(base, **variables)
                    result = self.run_script("all", "platform=iOS Simulator,id=test", bash=shell)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    args = self.args()
                    self.assertFalse(any(arg.startswith(("-only-testing:", "-skip-testing:")) for arg in args))

    def test_invalid_mode_is_reported_before_missing_xcode(self):
        self.env["PATH"] = str(self.bin_dir / "empty")
        self.env["HARNESS_XCODE_ACTION"] = "test-without-building"
        result = self.run_script("all", "platform=iOS Simulator,id=test")
        self.assertEqual(result.returncode, 2)
        self.assertIn("HARNESS_XCTESTRUN", result.stderr)
        self.assertNotIn("iOS tests not run", result.stderr)


if __name__ == "__main__":
    unittest.main()
