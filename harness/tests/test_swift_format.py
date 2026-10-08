"""Test Git selection and subprocess boundaries; exercise real Swift in CI."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GIT = shutil.which("git")


class SwiftFormatFixture(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.directory = Path(self.workspace.name).resolve()
        self.root = (self.directory / "repo").resolve()
        (self.root / "harness").mkdir(parents=True)
        (self.root / "src").mkdir()
        self.caller = self.directory / "caller"
        self.caller.mkdir()
        shutil.copyfile(ROOT / "harness/swift-format.py", self.root / "harness/swift-format.py")
        shutil.copyfile(ROOT / ".swift-format", self.root / ".swift-format")
        self.env = dict(os.environ)
        for key in ("HARNESS_FORMAT_BASE", "HARNESS_FORMAT_HEAD", "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"):
            self.env.pop(key, None)
        self.env["GIT_CONFIG_GLOBAL"] = os.devnull
        self.env["GIT_CONFIG_NOSYSTEM"] = "1"
        self.git("init", "--quiet")
        self.git("config", "user.name", "Harness test")
        self.git("config", "user.email", "harness@example.invalid")
        self.save_baseline()

    def git(self, *args):
        return subprocess.run(
            [GIT, *args], cwd=self.root, env=self.env, text=True, capture_output=True, check=True
        ).stdout.strip()

    def write(self, name, source="let value = 1\n"):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source, encoding="utf-8")
        return path

    def save_baseline(self):
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "fixture baseline")
        self.git("update-ref", "refs/remotes/origin/master", "HEAD")

    def run_script(self, *args):
        return subprocess.run(
            [sys.executable, str(self.root / "harness/swift-format.py"), *args],
            cwd=self.caller, env=self.env, text=True, capture_output=True,
        )


class SwiftFormatCommandTests(SwiftFormatFixture):
    def setUp(self):
        super().setUp()
        self.bin_dir = self.directory / "bin"
        self.bin_dir.mkdir()
        (self.bin_dir / "git").symlink_to(GIT)
        self.swift = self.bin_dir / "swift"
        self.invocation = self.directory / "invocation.json"
        self.swift.write_text(
            "#!" + sys.executable + "\n"
            "import json, os, pathlib, sys\n"
            "pathlib.Path(os.environ['HARNESS_TEST_INVOCATION']).write_text("
            "json.dumps({'args': sys.argv[1:], 'cwd': os.getcwd()}))\n"
            "sys.exit(int(os.environ.get('HARNESS_TEST_SWIFT_EXIT', '0')))\n",
            encoding="utf-8",
        )
        self.swift.chmod(0o755)
        self.env["PATH"] = str(self.bin_dir)
        self.env["HARNESS_TEST_INVOCATION"] = str(self.invocation)

    def selected_files(self):
        invocation = json.loads(self.invocation.read_text(encoding="utf-8"))
        args = invocation["args"]
        self.assertEqual(invocation["cwd"], str(self.root))
        self.assertEqual(args[args.index("--configuration") + 1], str(self.root / ".swift-format"))
        return args[args.index("--configuration") + 2:]

    def test_local_changes_are_combined_once_and_exclude_old_and_deleted(self):
        self.write("src/Existing.swift")
        deleted = self.write("src/Deleted.swift")
        renamed = self.write("src/Before.swift")
        self.write("old/Legacy.swift")
        self.save_baseline()

        self.write("src/Committed.swift")
        self.write("src/Existing.swift", "let value = 2\n")
        self.git("add", "src")
        self.git("commit", "--quiet", "-m", "committed Swift changes")
        self.write("src/Staged.swift")
        self.write("src/Existing.swift", "let value = 3\n")
        self.write("old/Legacy.swift", "let value = 2\n")
        deleted.unlink()
        renamed.rename(self.root / "src/After.swift")
        self.git("add", "src", "old")
        self.write("src/Existing.swift", "let value = 4\n")
        unusual = "src/日本語 file\nname.swift"
        self.write(unusual)
        self.write("src/readme.txt")

        result = self.run_script("lint")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.selected_files(),
            sorted(["src/After.swift", "src/Committed.swift", "src/Existing.swift", "src/Staged.swift", unusual]),
        )
        args = json.loads(self.invocation.read_text())["args"]
        self.assertEqual(args[:3], ["format", "lint", "--strict"])

    def test_explicit_format_uses_root_config_and_preserves_path_arguments(self):
        name = "src/space and\nnewline.swift"
        path = self.write(name)
        result = self.run_script("format", name, str(path))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.selected_files(), [name])
        args = json.loads(self.invocation.read_text())["args"]
        self.assertEqual(args[:3], ["format", "format", "--in-place"])

    def test_repository_alias_is_allowed_but_internal_source_links_are_rejected(self):
        source = self.write("src/Folder/Real.swift")
        alias = self.directory / "repo-alias"
        alias.symlink_to(self.root, target_is_directory=True)
        result = self.run_script("lint", str(alias / "src/Folder/Real.swift"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.selected_files(), ["src/Folder/Real.swift"])
        self.invocation.unlink()

        (self.root / "src/LinkedFile.swift").symlink_to(source)
        (self.root / "src/LinkedFolder").symlink_to(source.parent, target_is_directory=True)
        (self.root / "src/LinkedRoot").symlink_to(self.root, target_is_directory=True)
        for name in ("src/LinkedFile.swift", "src/LinkedFolder/Real.swift", "src/LinkedRoot/src/Folder/Real.swift"):
            with self.subTest(path=name):
                result = self.run_script("format", str(alias / name))
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse(self.invocation.exists())

    def test_invalid_explicit_files_fail_before_running_formatter(self):
        valid = self.write("src/Valid.swift")
        old = self.write("old/Legacy.swift")
        external = self.directory / "External.swift"
        external.write_text("let external = 1\n")
        (self.root / "src/Link.swift").symlink_to(external)
        (self.root / "src/LinkedDirectory").symlink_to(old.parent, target_is_directory=True)
        self.write("src/readme.txt")
        for invalid in (
            "old/Legacy.swift", "src/Missing.swift", "src/readme.txt", str(external),
            "src/Link.swift", "src/LinkedDirectory/Legacy.swift",
        ):
            with self.subTest(path=invalid):
                result = self.run_script("format", str(valid), invalid)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertFalse(self.invocation.exists())

    def test_default_selection_does_not_follow_file_or_directory_links(self):
        old = self.write("old/Legacy.swift")
        (self.root / "src/Link.swift").symlink_to(old)
        (self.root / "src/LinkedDirectory").symlink_to(old.parent, target_is_directory=True)
        self.write("src/Regular.swift")
        result = self.run_script("lint")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.selected_files(), ["src/Regular.swift"])

    def test_no_targets_is_distinct_from_missing_formatter(self):
        self.swift.unlink()
        self.write("old/Legacy.swift")
        result = self.run_script("lint")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("tool not run", result.stdout)
        self.write("src/Target.swift")
        result = self.run_script("lint")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Swift format not run", result.stderr)
        self.assertFalse(self.invocation.exists())

    def test_formatter_exit_code_is_propagated(self):
        self.write("src/Target.swift")
        self.env["HARNESS_TEST_SWIFT_EXIT"] = "65"
        self.assertEqual(self.run_script("lint").returncode, 65)

    def test_invalid_or_unpaired_ci_refs_fail_without_running_formatter(self):
        self.write("src/Target.swift")
        for refs in (
            {"HARNESS_FORMAT_BASE": "HEAD"},
            {"HARNESS_FORMAT_HEAD": "HEAD"},
            {"HARNESS_FORMAT_BASE": "missing-ref", "HARNESS_FORMAT_HEAD": "HEAD"},
            {"HARNESS_FORMAT_BASE": "HEAD", "HARNESS_FORMAT_HEAD": "missing-ref"},
            {"HARNESS_FORMAT_BASE": "", "HARNESS_FORMAT_HEAD": "HEAD"},
        ):
            with self.subTest(refs=refs):
                self.env.pop("HARNESS_FORMAT_BASE", None)
                self.env.pop("HARNESS_FORMAT_HEAD", None)
                self.env.update(refs)
                result = self.run_script("lint")
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.invocation.exists())

    def test_missing_local_base_is_a_git_failure(self):
        self.git("update-ref", "-d", "refs/remotes/origin/master")
        result = self.run_script("lint")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Git selection failed", result.stderr)
        self.assertFalse(self.invocation.exists())

    def test_ci_uses_merge_base_and_excludes_local_working_changes(self):
        self.write("src/Original.swift")
        self.save_baseline()
        base = self.git("rev-parse", "HEAD")
        self.write("src/Feature.swift")
        self.git("add", "src")
        self.git("commit", "--quiet", "-m", "feature")
        head = self.git("rev-parse", "HEAD")
        self.git("checkout", "--quiet", "-b", "base-later", base)
        self.write("src/Original.swift", "let value = 9\n")
        self.git("add", "src")
        self.git("commit", "--quiet", "-m", "base advanced independently")
        self.env["HARNESS_FORMAT_BASE"] = self.git("rev-parse", "HEAD")
        self.env["HARNESS_FORMAT_HEAD"] = head
        self.git("checkout", "--quiet", "--detach", head)
        self.write("src/Staged.swift")
        self.git("add", "src/Staged.swift")
        self.write("src/Original.swift", "let value = 8\n")
        self.write("src/Untracked.swift")
        result = self.run_script("lint")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.selected_files(), ["src/Feature.swift"])

    def test_zero_base_on_initial_push_selects_head_sources(self):
        self.write("src/Initial.swift")
        self.write("old/Legacy.swift")
        self.save_baseline()
        self.env["HARNESS_FORMAT_BASE"] = "0" * 40
        self.env["HARNESS_FORMAT_HEAD"] = "HEAD"
        result = self.run_script("lint")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.selected_files(), ["src/Initial.swift"])


class RealSwiftFormatTests(SwiftFormatFixture):
    def test_real_lint_failure_and_format_recovery(self):
        swift = shutil.which("swift")
        required = os.environ.get("HARNESS_REQUIRE_SWIFT_FORMAT") == "1"
        if swift is None:
            if required:
                self.fail("CI requires the real swift format tool; swift is unavailable")
            self.skipTest("Real swift format not run: swift is unavailable")

        version = subprocess.run([swift, "format", "--version"], capture_output=True, text=True, env=self.env)
        if version.returncode != 0:
            if required:
                self.fail("CI requires swift format: " + version.stderr)
            self.skipTest("Real swift format not run: toolchain has no usable swift format")

        name = "src/Example.swift"
        source = self.write(name, "struct Example {\n    let value = 1\n}\n")
        result = self.run_script("lint", name)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        source.write_text("struct Example{\nlet value=1\n}\n", encoding="utf-8")
        result = self.run_script("lint", name)
        self.assertNotEqual(result.returncode, 0, "Real formatter accepted the formatting violation")
        result = self.run_script("format", name)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.run_script("lint", name)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
