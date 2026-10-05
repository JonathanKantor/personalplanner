"""CLI tests (annex of cli/commands.jac; run: jac test cli/commands.jac).

Only the pure parts are tested here; the commands themselves were exercised
against a running server (see README "CLI").
"""

import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }

def tz -> ZoneInfo {
    return ZoneInfo("America/Detroit");
}

def today -> datetime {
    return datetime.now(tz());
}

test "today and tomorrow" {
    assert resolve_due("today", tz()) == today().date().isoformat();
    assert resolve_due("tomorrow 09:30", tz()) == (today() + timedelta(days=1)).date().isoformat() + "T09:30";
}

test "weekday names mean the next such day, never today" {
    for (i, name) in enumerate(["mon", "Tuesday", "WED", "thu", "fri", "sat", "sun"]) {
        d = datetime.fromisoformat(resolve_due(name, tz()));
        assert d.weekday() == i;
        assert 1 <= (d.date() - today().date()).days and (d.date() - today().date()).days <= 7;
    }
}

test "ISO dates pass through, with a space allowed before the time" {
    assert resolve_due("2026-10-09", tz()) == "2026-10-09";
    assert resolve_due("2026-10-09 17:00", tz()) == "2026-10-09T17:00";
}

test "unreadable dates list the accepted forms" {
    with testraises(CliError, `match="today, tomorrow, fri") {
        resolve_due("someday", tz());
    }
}

test "id prefixes must be unique" {
    items = [{"id": "abc111"}, {"id": "abd222"}];
    assert _resolve("abc", items, "task")["id"] == "abc111";
    with testraises(CliError, `match="matches 2") {
        _resolve("ab", items, "task");
    }
    with testraises(CliError, `match="No task") {
        _resolve("zz", items, "task");
    }
}
