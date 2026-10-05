"""Recurrence tests (run: jac test core/recurrence.jac)."""

import from datetime { datetime }
import from zoneinfo { ZoneInfo }

glob TZ: str = "America/Detroit";

def local(y: int, m: int, d: int, h: int = 17) -> datetime {
    return datetime(y, m, d, h, tzinfo=ZoneInfo(TZ));
}

def days_of(dues: list[datetime]) -> list[str] {
    return [d.astimezone(ZoneInfo(TZ)).strftime("%a %d") for d in dues];
}

test "weekly rule picks the listed weekdays" {
    # First due Mon Oct 19; next ones within the following week.
    dues = next_dues("WEEKLY:MO,WE", local(2026, 10, 19), local(2026, 10, 28), TZ);
    assert days_of(dues) == ["Wed 21", "Mon 26", "Wed 28"], days_of(dues);
}

test "daily rule with UNTIL stops on that date" {
    dues = next_dues("DAILY;UNTIL=2026-10-22", local(2026, 10, 19), local(2026, 11, 30), TZ);
    assert days_of(dues) == ["Tue 20", "Wed 21", "Thu 22"];
}

test "wall-clock time is kept across DST" {
    dues = next_dues("WEEKLY:FR", local(2026, 10, 30), local(2026, 11, 7), TZ);
    assert [d.astimezone(ZoneInfo(TZ)).hour for d in dues] == [17];
    assert dues[0].astimezone(ZoneInfo("UTC")).hour == 22;     # 5pm EST
}

test "lowercase and spaces are accepted" {
    assert parse_rule(" weekly:mo, fr ").weekdays == [0, 4];
}

test "bad rules explain the format" {
    for bad in ["MONTHLY", "WEEKLY:XX", "WEEKLY:", "DAILY;UNTIL=soon", "DAILY;COUNT=3"] {
        with testraises(ValueError, `match="DAILY or WEEKLY") {
            parse_rule(bad);
        }
    }
}
