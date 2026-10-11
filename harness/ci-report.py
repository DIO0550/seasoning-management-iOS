#!/usr/bin/env python3
"""Pass compact Xcode results to the comment job without uploading artifacts."""

import json
import math
import os
import re
import subprocess
import sys
from pathlib import Path


OUTPUTS = {
    "SeasoningManagerTests": "unit_report",
    "SeasoningManagerUITests": "ui_report",
}
MAX_OUTPUT_CHARACTERS = 60_000  # ASCII JSON fits Actions outputs and a Linux env variable.


def duration_seconds(value):
    if not isinstance(value, str):
        return None
    number = r"(\d+(?:\.\d+)?)"
    match = re.fullmatch(rf"(?:{number}d\s*)?(?:{number}h\s*)?(?:{number}m\s*)?(?:{number}s)?", value.strip())
    if match is None or not any(match.groups()):
        return None
    seconds = sum(float(part or 0) * unit for part, unit in zip(match.groups(), (86400, 3600, 60, 1)))
    return seconds if math.isfinite(seconds) else None


def read_result(arguments, errors, name):
    try:
        result = subprocess.run(["xcrun", *arguments], capture_output=True, text=True, check=True)
        value = json.loads(result.stdout)
        if not isinstance(value, dict):
            raise ValueError("Expected an object")
        return value
    except (OSError, subprocess.CalledProcessError, ValueError) as error:
        print(f"::warning::Could not read {name}: {type(error).__name__}", file=sys.stderr)
        errors.append(name)
        return None


def app_coverage(report):
    if not isinstance(report, dict) or not isinstance(report.get("targets"), list):
        return None
    app = next((target for target in report["targets"]
                if isinstance(target, dict) and target.get("name") == "SeasoningManager.app"), None)
    if app is None:
        return None
    coverage = {key: app.get(key) for key in ("coveredLines", "executableLines")}
    coverage["files"] = None
    if isinstance(app.get("files"), list):
        coverage["files"] = [
            {key: item.get(key) for key in ("path", "coveredLines", "executableLines")}
            for item in app["files"] if isinstance(item, dict)
        ]
    return coverage


def test_cases(report):
    if not isinstance(report, dict) or not isinstance(report.get("testNodes"), list):
        return None
    results = []
    pending = list(reversed(report["testNodes"]))
    while pending:
        node = pending.pop()
        if not isinstance(node, dict):
            continue
        if node.get("nodeType") == "Test Case":
            results.append({
                "name": node.get("nodeIdentifier") or node.get("name"),
                "result": node.get("result"),
                "seconds": duration_seconds(node.get("duration")),
            })
            continue  # Failure messages / parameter children are not extra test cases.
        children = node.get("children")
        if isinstance(children, list):
            pending.extend(reversed(children))
    return results


def encode_output(report):
    report["omitted"] = {"files": 0, "tests": 0}
    lists = [report.get("tests"), (report.get("coverage") or {}).get("files")]
    # Retain the slowest tests / lowest coverage if transport limits force omission.
    if lists[0]:
        lists[0].sort(key=lambda item: item["seconds"] if item["seconds"] is not None else -1,
                      reverse=True)
    if lists[1]:
        lists[1].sort(key=coverage_ratio)
    encoded = json.dumps(report, separators=(",", ":"))
    while len(encoded) > MAX_OUTPUT_CHARACTERS:
        candidates = [(len(items), key, items) for key, items in zip(("tests", "files"), lists)
                      if items]
        if not candidates:
            raise ValueError("Report exceeds the job-output limit")
        _, key, items = max(candidates, key=lambda entry: entry[0])
        removed = max(1, len(items) // 2)
        del items[-removed:]
        report["omitted"][key] += removed
        encoded = json.dumps(report, separators=(",", ":"))
    return encoded


def coverage_ratio(item):
    covered, executable = item.get("coveredLines"), item.get("executableLines")
    if type(covered) is not int or type(executable) is not int:
        return math.inf
    if not 0 <= covered <= executable or executable == 0:
        return math.inf
    return covered / executable


def main():
    target = os.environ["TEST_TARGET"]
    output_name = OUTPUTS[target]
    bundle = os.environ["HARNESS_RESULT_BUNDLE"]
    report = {"runId": os.environ["GITHUB_RUN_ID"], "attempt": os.environ["GITHUB_RUN_ATTEMPT"],
              "summary": None, "coverage": None, "tests": None, "errors": []}
    if Path(bundle).is_dir():
        summary = read_result(["xcresulttool", "get", "test-results", "summary", "--path", bundle],
                              report["errors"], "summary")
        tests = read_result(["xcresulttool", "get", "test-results", "tests", "--path", bundle],
                            report["errors"], "tests")
        coverage = read_result(["xccov", "view", "--report", "--json", bundle],
                               report["errors"], "coverage")
        if summary is not None:
            report["summary"] = {key: summary.get(key) for key in
                                 ("passedTests", "failedTests", "skippedTests")}
        report["tests"] = test_cases(tests)
        report["coverage"] = app_coverage(coverage)
    else:
        print("::warning::No result bundle; test results and coverage are unavailable.")

    with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as stream:
        stream.write(f"{output_name}={encode_output(report)}\n")
    return int(bool(report["errors"]))


if __name__ == "__main__":
    sys.exit(main())
