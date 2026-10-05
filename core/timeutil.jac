"""Time helpers shared by the server and scheduler.

Rule of thumb: store UTC, show local. Every datetime stored on the graph is an
ISO string in UTC; the user's timezone (from Preferences) is applied only when
reading input or formatting output.
"""

import from datetime { datetime, timezone, time, timedelta }
import from zoneinfo { ZoneInfo, ZoneInfoNotFoundError }

def now_utc -> datetime {
    return datetime.now(timezone.utc);
}

def to_iso(dt: datetime) -> str {
    return dt.astimezone(timezone.utc).isoformat();
}

def from_iso(s: str) -> datetime {
    return datetime.fromisoformat(s);
}

def zone(tz_name: str) -> ZoneInfo {
    try {
        return ZoneInfo(tz_name);
    } except (ZoneInfoNotFoundError, ValueError) {
        raise ValueError(f"Unknown timezone '{tz_name}' (use an IANA name like America/Detroit)");
    }
}

"""Parse "HH:MM" into a time, or raise ValueError."""
def parse_hhmm(s: str) -> time {
    try {
        return datetime.strptime(s, "%H:%M").time();
    } except ValueError {
        raise ValueError(f"Expected a time like 09:30, got '{s}'");
    }
}

"""Parse a user-supplied due date into a UTC ISO string.

Accepts "2026-10-09" (meaning end of that day, 23:59 local),
"2026-10-09T17:00" / "2026-10-09 17:00" (local time), or a full ISO string
with an offset.
"""
def parse_due(text: str, tz_name: str) -> str {
    text = text.strip();
    if not text {
        raise ValueError("A due date is required, e.g. 2026-10-09 or 2026-10-09T17:00");
    }
    try {
        dt = datetime.fromisoformat(text);
    } except ValueError {
        raise ValueError(f"Could not read due date '{text}'; use YYYY-MM-DD or YYYY-MM-DDTHH:MM");
    }
    if len(text) == 10 {                       # date only -> end of day
        dt = dt.replace(hour=23, minute=59);
    }
    if dt.tzinfo is None {                     # no offset given -> user's local time
        dt = dt.replace(tzinfo=zone(tz_name));
    }
    return to_iso(dt);
}

"""Format a stored UTC ISO string in the user's timezone, e.g. "Thu Oct 9 17:00"."""
def local_label(iso: str, tz_name: str) -> str {
    if not iso {
        return "";
    }
    dt = from_iso(iso).astimezone(zone(tz_name));
    return f"{dt.strftime('%a %b')} {dt.day} {dt.strftime('%H:%M')}";
}

"""Monday 00:00 local of the week containing `day`, returned as a UTC datetime."""
def week_start(day: datetime, tz_name: str) -> datetime {
    local = day.astimezone(zone(tz_name));
    monday = (local - timedelta(days=local.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    );
    return monday.astimezone(timezone.utc);
}
