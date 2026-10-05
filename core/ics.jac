"""Parse iCalendar (.ics) text into Occurrences.

Pure functions only (no graph access), so they are easy to test.
Python libraries are used directly from Jac: `icalendar` parses the file and
`recurring_ical_events` expands RRULE/RDATE/EXDATE and moved instances into
concrete occurrences. They are installed into .jac/venv via `jac install`.
"""

import icalendar;
import recurring_ical_events;
import x_wr_timezone;
import from datetime { datetime, date, timedelta, timezone }
import from core.models { Occurrence }
import from core.timeutil { zone, to_iso }

"""Turn an ics date or datetime into an aware datetime.
- date (all-day)       -> local midnight in the user's timezone
- naive ("floating")   -> interpreted in the user's timezone
- aware                -> unchanged
"""
def _aware(value: any, tz_name: str) -> datetime {
    if isinstance(value, datetime) {
        if value.tzinfo is None {
            return value.replace(tzinfo=zone(tz_name));
        }
        return value;
    }
    d = value as date;
    return datetime(d.year, d.month, d.day, tzinfo=zone(tz_name));
}

"""Read an .ics string. Raises ValueError with a readable message if it isn't one."""
def parse_calendar(text: str) -> any {
    try {
        cal = icalendar.Calendar.from_ical(text);
    } except Exception as e {
        raise ValueError(f"Not a valid .ics file: {str(e)}");
    }
    # Google exports put the zone in X-WR-TIMEZONE; this applies it properly.
    return x_wr_timezone.to_standard(cal);
}

def calendar_name(cal: any, fallback: str) -> str {
    name = cal.get("X-WR-CALNAME");
    return str(name) if name else fallback;
}

"""Every occurrence of every event that overlaps [window_start, window_end)."""
def expand_occurrences(
    cal: any, window_start: datetime, window_end: datetime, tz_name: str
) -> list[Occurrence] {
    # UIDs whose master event repeats. (Expanded copies lose their RRULE, so
    # this has to be read from the original events.)
    recurring: set[str] = set();
    for comp in cal.walk("VEVENT") {
        if "RRULE" in comp or "RDATE" in comp or "RECURRENCE-ID" in comp {
            recurring.add(str(comp.get("UID", "")));
        }
    }

    result: list[Occurrence] = [];
    for ev in recurring_ical_events.of(cal).between(window_start, window_end) {
        if str(ev.get("STATUS", "")).upper() == "CANCELLED" {
            continue;
        }
        raw_start = ev["DTSTART"].dt;
        all_day = not isinstance(raw_start, datetime);
        start = _aware(raw_start, tz_name);
        if "DTEND" in ev {
            end = _aware(ev["DTEND"].dt, tz_name);
        } elif "DURATION" in ev {
            end = start + ev["DURATION"].dt;
        } else {
            end = start + (timedelta(days=1) if all_day else timedelta(0));
        }
        uid = str(ev.get("UID", ""));
        # RECURRENCE-ID = the slot this occurrence originally occupied. It stays
        # the same even if one instance is moved, so it makes a stable id.
        rid = ev.get("RECURRENCE-ID");
        original = _aware(rid.dt, tz_name) if rid else start;
        result.append(
            Occurrence(
                external_id=f"{uid}@{to_iso(original)}",
                series_id=uid if uid in recurring else "",
                title=str(ev.get("SUMMARY", "(no title)")),
                start=to_iso(start),
                end=to_iso(end),
                all_day=all_day
            )
        );
    }
    result.sort(key=lambda (o: Occurrence) { o.start; });
    return result;
}

"""Turn webcal:// links (what calendar apps hand out) into https://."""
def normalize_url(url: str) -> str {
    url = url.strip();
    if url.startswith("webcal://") {
        return "https://" + url[len("webcal://"):];
    }
    if not (url.startswith("https://") or url.startswith("http://")) {
        raise ValueError("Calendar URL must start with https://, http://, or webcal://");
    }
    return url;
}
