"""Tests for .ics parsing (annex of core/ics.jac; run: jac test core/ics.jac).

A `.test.jac` file is an "annex": it sees everything declared in ics.jac
without importing it. `test "name" { ... }` blocks only run under `jac test`.
"""

import from datetime { datetime }
import from zoneinfo { ZoneInfo }

glob TZ: str = "America/Detroit";

def _window(a: str, b: str) -> tuple[datetime, datetime] {
    return (
        datetime.fromisoformat(a).replace(tzinfo=ZoneInfo(TZ)),
        datetime.fromisoformat(b).replace(tzinfo=ZoneInfo(TZ))
    );
}

def _parse(body: str, a: str = "2026-10-01", b: str = "2026-12-31") -> list[Occurrence] {
    text = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\n" + body + "END:VCALENDAR\r\n";
    (s, e) = _window(a, b);
    return expand_occurrences(parse_calendar(text), s, e, TZ);
}

def _local_hour(iso: str) -> int {
    return datetime.fromisoformat(iso).astimezone(ZoneInfo(TZ)).hour;
}

# A weekly Monday lecture: 4 weeks, one week cancelled (EXDATE), one moved.
glob LECTURE: str = """BEGIN:VEVENT
UID:lec1
SUMMARY:Lecture
DTSTART;TZID=America/Detroit:20261019T100000
DTEND;TZID=America/Detroit:20261019T113000
RRULE:FREQ=WEEKLY;BYDAY=MO;COUNT=4
EXDATE;TZID=America/Detroit:20261026T100000
END:VEVENT
BEGIN:VEVENT
UID:lec1
RECURRENCE-ID;TZID=America/Detroit:20261102T100000
SUMMARY:Lecture (moved)
DTSTART;TZID=America/Detroit:20261102T140000
DTEND;TZID=America/Detroit:20261102T153000
END:VEVENT
""";

test "weekly event expands, skipping EXDATE" {
    occ = _parse(LECTURE);
    assert len(occ) == 3, f"expected 3 occurrences, got {len(occ)}";
    assert all(o.series_id == "lec1" for o in occ);
}

test "moved instance keeps the original slot's id" {
    occ = _parse(LECTURE);
    moved = [o for o in occ if o.title == "Lecture (moved)"][0];
    # id is based on the ORIGINAL 10:00 slot, so a re-sync after a move updates
    # the same stored event instead of adding a new one.
    assert moved.external_id == "lec1@2026-11-02T15:00:00+00:00", moved.external_id;
    assert _local_hour(moved.start) == 14;
}

test "local time survives the DST change" {
    # DST ends Nov 1 2026. 10:00 local is 14:00 UTC before and 15:00 UTC after.
    occ = [o for o in _parse(LECTURE) if o.title == "Lecture"];
    assert [_local_hour(o.start) for o in occ] == [10, 10];
    assert [datetime.fromisoformat(o.start).hour for o in occ] == [14, 15];
}

test "window limits the occurrences" {
    occ = _parse(LECTURE, "2026-10-01", "2026-10-25");
    assert len(occ) == 1;
}

test "one-off event has no series" {
    occ = _parse("BEGIN:VEVENT\nUID:x\nSUMMARY:Dentist\nDTSTART:20261015T130000Z\nDTEND:20261015T140000Z\nEND:VEVENT\n");
    assert len(occ) == 1 and occ[0].series_id == "";
    assert occ[0].start == "2026-10-15T13:00:00+00:00";      # Z time kept as UTC
}

test "all-day event starts at local midnight" {
    occ = _parse("BEGIN:VEVENT\nUID:h\nSUMMARY:Fall break\nDTSTART;VALUE=DATE:20261019\nDTEND;VALUE=DATE:20261021\nEND:VEVENT\n");
    assert occ[0].all_day;
    assert occ[0].start == "2026-10-19T04:00:00+00:00";      # 00:00 EDT
    assert occ[0].end == "2026-10-21T04:00:00+00:00";        # end date is exclusive
}

test "floating time uses the user's timezone" {
    occ = _parse("BEGIN:VEVENT\nUID:f\nSUMMARY:Gym\nDTSTART:20261015T080000\nDTEND:20261015T090000\nEND:VEVENT\n");
    assert _local_hour(occ[0].start) == 8;
}

test "X-WR-TIMEZONE (Google export style) is respected" {
    text = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-TIMEZONE:America/Los_Angeles\r\n"
        + "BEGIN:VEVENT\r\nUID:w\r\nSUMMARY:West coast call\r\nDTSTART:20261015T090000\r\n"
        + "DTEND:20261015T100000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n";
    (s, e) = _window("2026-10-01", "2026-11-01");
    occ = expand_occurrences(parse_calendar(text), s, e, TZ);
    assert _local_hour(occ[0].start) == 12;                   # 9am PT = noon ET
}

test "cancelled events are skipped" {
    occ = _parse("BEGIN:VEVENT\nUID:c\nSUMMARY:Gone\nSTATUS:CANCELLED\nDTSTART:20261015T130000Z\nDTEND:20261015T140000Z\nEND:VEVENT\n");
    assert len(occ) == 0;
}

test "garbage input is a readable error" {
    with testraises(ValueError, `match="Not a valid .ics") {
        parse_calendar("this is not a calendar");
    }
}

test "webcal links become https" {
    assert normalize_url("webcal://example.com/a.ics") == "https://example.com/a.ics";
    with testraises(ValueError) {
        normalize_url("ftp://example.com/a.ics");
    }
}
