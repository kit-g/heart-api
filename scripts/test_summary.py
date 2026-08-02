#!/usr/bin/env python3
"""Turn raw test output into one markdown table for the GitHub Actions job summary.

Every test job in `.github/workflows/deploy-api.yml` drops a small file into a
`test-reports/` directory and uploads it as an artifact; a final job downloads
them all and runs this to render a single view.

Two input formats, told apart by extension:

  *.json  `dart test --file-reporter=json` output — newline-delimited events.
          Counted from `testDone` events, ignoring the synthetic "loading …"
          suites the reporter emits per file.
  *.tap   captured `pg_prove` stdout. Read from its trailing
          "Files=N, Tests=N" / "Result: PASS" summary.

Usage:  test_summary.py <report-dir> [<coverage-file>]

Writes markdown to stdout. Exit status is always 0 — this reports on a run, it
does not judge it; the test steps themselves decide whether the build fails.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys
from dataclasses import dataclass, field


@dataclass
class Suite:
    name: str
    passed: int = 0
    failed: int = 0
    skipped: int = 0
    seconds: float = 0.0
    failures: list[str] = field(default_factory=list)

    @property
    def total(self) -> int:
        return self.passed + self.failed + self.skipped

    @property
    def ok(self) -> bool:
        return self.failed == 0 and self.total > 0


def parse_dart(path: pathlib.Path) -> Suite:
    """Count testDone events from the Dart JSON reporter's event stream."""
    suite = Suite(name=path.stem)
    names: dict[int, str] = {}

    for line in path.read_text().splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        match event.get("type"):
            case "testStart":
                test = event.get("test", {})
                names[test.get("id")] = test.get("name", "")
            case "testDone":
                # The reporter emits a synthetic "loading <file>" test per suite;
                # counting those would inflate every total by the file count.
                name = names.get(event.get("testID"), "")
                if event.get("hidden") or name.startswith("loading "):
                    continue
                match (event.get("result"), event.get("skipped")):
                    case (_, True):
                        suite.skipped += 1
                    case ("success", _):
                        suite.passed += 1
                    case _:
                        suite.failed += 1
                        suite.failures.append(name)
            case "done":
                suite.seconds = round(event.get("time", 0) / 1000, 1)

    return suite


def parse_tap(path: pathlib.Path) -> Suite:
    """Read pg_prove's trailing summary rather than the whole TAP stream.

    Counts come from the "Test Summary Report" block, whose per-file
    `(Wstat: N Tests: N Failed: N)` line is authoritative — the `Failed test: N`
    lines are printed twice, inline and again in the report, so counting those
    doubles every failure.
    """
    text = path.read_text()
    suite = Suite(name=path.stem)

    if counts := re.search(r"Files=(\d+),\s*Tests=(\d+)", text):
        suite.passed = int(counts.group(2))

    for report in re.finditer(r"^(\S+\.sql)\s*\(Wstat:.*?Failed:\s*(\d+)\)", text, re.MULTILINE):
        failed = int(report.group(2))
        if failed:
            suite.failed += failed
            suite.passed = max(0, suite.passed - failed)
            suite.failures.append(f"{report.group(1)} ({failed} assertion(s))")

    if re.search(r"^Result:\s*FAIL", text, re.MULTILINE) and suite.failed == 0:
        # Failed for a reason the report did not enumerate — a bad plan, a file
        # that would not parse, a connection that dropped.
        suite.failed = 1
        suite.failures.append("pg_prove reported FAIL; see the job log")

    return suite


def coverage_line(path: pathlib.Path) -> str | None:
    """`tool/check_coverage.dart` prints one line; quote it verbatim."""
    if not path.exists():
        return None
    text = path.read_text().strip()
    return text.splitlines()[-1].strip() if text else None


def render(suites: list[Suite], coverage: str | None) -> str:
    out: list[str] = ["## Test results", ""]

    if not suites:
        return "\n".join(out + ["No test reports were produced."])

    out += [
        "| Suite | Result | Passed | Failed | Skipped | Time |",
        "|---|---|--:|--:|--:|--:|",
    ]
    for suite in sorted(suites, key=lambda s: s.name):
        icon = "✅" if suite.ok else "❌"
        time = f"{suite.seconds}s" if suite.seconds else "—"
        out.append(
            f"| `{suite.name}` | {icon} | {suite.passed} | {suite.failed} "
            f"| {suite.skipped or '—'} | {time} |"
        )

    total_passed = sum(s.passed for s in suites)
    total_failed = sum(s.failed for s in suites)
    total_skipped = sum(s.skipped for s in suites)
    out.append(
        f"| **Total** | {'✅' if total_failed == 0 else '❌'} | **{total_passed}** "
        f"| **{total_failed}** | **{total_skipped or '—'}** | |"
    )
    out.append("")

    if coverage:
        out += [f"**Coverage** — {coverage}", ""]

    # Name what broke, so the summary is actionable without opening the logs.
    if failing := [s for s in suites if s.failures]:
        out += ["### Failures", ""]
        for suite in failing:
            out.append(f"**`{suite.name}`**")
            out += [f"- {name}" for name in suite.failures[:25]]
            if len(suite.failures) > 25:
                out.append(f"- …and {len(suite.failures) - 25} more")
            out.append("")

    return "\n".join(out)


def main() -> int:
    reports = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "test-reports")
    coverage = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path("coverage.txt")

    suites: list[Suite] = []
    for path in sorted(reports.rglob("*")):
        match path.suffix:
            case ".json":
                suites.append(parse_dart(path))
            case ".tap":
                suites.append(parse_tap(path))

    print(render(suites, coverage_line(coverage)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
