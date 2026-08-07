"""
test_summary parser tests. Pure-function coverage: feed parse_dart minimal
`dart test --file-reporter=json` streams and parse_tap pg_prove captures, both
written to tmp_path — no real test runs involved.

Run scoped (see README.md): uv run pytest scripts/tests -o pythonpath=scripts
"""

import json

from test_summary import Suite, parse_dart, parse_tap, render


def _dart_report(tmp_path, name, events):
    path = tmp_path / f"{name}.json"
    path.write_text("\n".join(json.dumps(e) for e in events) + "\n")
    return path


def _start(test_id, name):
    return {"type": "testStart", "test": {"id": test_id, "name": name}}


def _done(test_id, result="success", **extra):
    return {"type": "testDone", "testID": test_id, "result": result, **extra}


class TestParseDart:
    def test_all_passing(self, tmp_path):
        suite = parse_dart(
            _dart_report(
                tmp_path,
                "api",
                [
                    _start(1, "loading test/a_test.dart"),
                    _done(1),  # synthetic loader; must not count
                    _start(2, "adds two numbers"),
                    _done(2),
                    _start(3, "formats a date"),
                    _done(3),
                    {"type": "done", "time": 4321},
                ],
            )
        )
        assert suite.name == "api"
        assert (suite.passed, suite.failed, suite.skipped) == (2, 0, 0)
        assert suite.seconds == 4.3
        assert suite.failures == []
        assert suite.ok

    def test_failing_test_is_counted_and_named(self, tmp_path):
        suite = parse_dart(
            _dart_report(
                tmp_path,
                "api",
                [
                    _start(1, "works"),
                    _done(1),
                    _start(2, "breaks"),
                    _done(2, result="error"),
                ],
            )
        )
        assert (suite.passed, suite.failed) == (1, 1)
        assert suite.failures == ["breaks"]
        assert not suite.ok

    def test_skipped_test(self, tmp_path):
        suite = parse_dart(
            _dart_report(
                tmp_path,
                "api",
                [_start(1, "flaky on ci"), _done(1, skipped=True)],
            )
        )
        assert (suite.passed, suite.failed, suite.skipped) == (0, 0, 1)

    def test_hidden_and_non_json_lines_are_ignored(self, tmp_path):
        path = tmp_path / "api.json"
        path.write_text(
            "Observatory listening on http://127.0.0.1\n"
            + json.dumps(_start(1, "real test"))
            + "\n"
            + json.dumps(_done(1))
            + "\n"
            + json.dumps(_done(2, hidden=True))
            + "\n{not json\n"
        )
        suite = parse_dart(path)
        assert (suite.passed, suite.failed, suite.skipped) == (1, 0, 0)


def _tap_report(tmp_path, text):
    path = tmp_path / "db.tap"
    path.write_text(text)
    return path


class TestParseTap:
    def test_passing_summary(self, tmp_path):
        suite = parse_tap(
            _tap_report(
                tmp_path,
                "All tests successful.\n"
                "Files=3, Tests=120,  5 wallclock secs\n"
                "Result: PASS\n",
            )
        )
        assert suite.name == "db"
        assert (suite.passed, suite.failed) == (120, 0)
        assert suite.ok

    def test_failing_report_block(self, tmp_path):
        suite = parse_tap(
            _tap_report(
                tmp_path,
                "Test Summary Report\n"
                "-------------------\n"
                "workouts.sql (Wstat: 256 Tests: 40 Failed: 2)\n"
                "  Failed tests:  7, 12\n"
                "sessions.sql (Wstat: 0 Tests: 30 Failed: 0)\n"
                "Files=3, Tests=120,  5 wallclock secs\n"
                "Result: FAIL\n",
            )
        )
        assert (suite.passed, suite.failed) == (118, 2)
        assert suite.failures == ["workouts.sql (2 assertion(s))"]
        assert not suite.ok

    def test_fail_without_enumerated_failures(self, tmp_path):
        # Bad plan / parse error / dropped connection: FAIL, but no per-file
        # Failed: N counts to attribute.
        suite = parse_tap(
            _tap_report(
                tmp_path,
                "Files=1, Tests=0,  0 wallclock secs\nResult: FAIL\n",
            )
        )
        assert suite.failed == 1
        assert suite.failures == ["pg_prove reported FAIL; see the job log"]
        assert not suite.ok

    def test_empty_file(self, tmp_path):
        suite = parse_tap(_tap_report(tmp_path, ""))
        assert (suite.passed, suite.failed, suite.skipped) == (0, 0, 0)
        # Zero tests is not a pass — ok requires total > 0.
        assert not suite.ok


class TestRender:
    def test_no_suites(self):
        assert "No test reports were produced." in render([], None)

    def test_table_totals_coverage_and_failures(self):
        suites = [
            Suite(name="db", passed=118, failed=2, failures=["workouts.sql (2 assertion(s))"]),
            Suite(name="api", passed=10, skipped=1, seconds=4.3),
        ]
        out = render(suites, "line coverage: 92.1%")
        lines = out.splitlines()

        assert "| `api` | ✅ | 10 | 0 | 1 | 4.3s |" in lines
        assert "| `db` | ❌ | 118 | 2 | — | — |" in lines
        # Sorted by name: api before db.
        assert lines.index("| `api` | ✅ | 10 | 0 | 1 | 4.3s |") < lines.index(
            "| `db` | ❌ | 118 | 2 | — | — |"
        )
        assert "| **Total** | ❌ | **128** | **2** | **1** | |" in lines
        assert "**Coverage** — line coverage: 92.1%" in lines
        assert "### Failures" in lines
        assert "- workouts.sql (2 assertion(s))" in lines

    def test_all_green_omits_failures_section(self):
        out = render([Suite(name="api", passed=3)], None)
        assert "### Failures" not in out
        assert "Coverage" not in out
        assert "| **Total** | ✅ | **3** | **0** | **—** | |" in out
