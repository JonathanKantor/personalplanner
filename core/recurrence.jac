"""Recurring tasks: a deliberately small rule format.

    DAILY                     every day
    WEEKLY:MO,WE,FR           on those weekdays
    ...;UNTIL=2026-12-15      optional last date (inclusive)

A recurring task is itself the first occurrence. Later occurrences are created
as separate tasks (with parent_id pointing at the first one) shortly before
they are needed, so each one can be scheduled and checked off on its own.
Pure functions only.
"""

import from datetime { datetime, date, timedelta }
import from core.timeutil { zone }

glob CODES: list[str] = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];

obj Rule {
    has weekdays: list[int],         # 0=Monday; all 7 for DAILY
        until: date | None = None;
}

"""Parse a rule string, or raise ValueError explaining the format."""
def parse_rule(text: str) -> Rule {
    help = "use DAILY or WEEKLY:MO,WE (optionally ;UNTIL=YYYY-MM-DD)";
    parts = text.strip().upper().split(";");
    head = parts[0];
    until: date | None = None;
    for extra in parts[1:] {
        if not extra.startswith("UNTIL=") {
            raise ValueError(f"Unknown recurrence option '{extra}'; {help}");
        }
        try {
            until = date.fromisoformat(extra[len("UNTIL="):]);
        } except ValueError {
            raise ValueError(f"Bad UNTIL date in '{text}'; {help}");
        }
    }
    if head == "DAILY" {
        return Rule(weekdays=list(range(7)), until=until);
    }
    if head.startswith("WEEKLY:") {
        days = [d.strip() for d in head[len("WEEKLY:"):].split(",") if d.strip()];
        if not days or any(d not in CODES for d in days) {
            raise ValueError(f"Bad weekday list in '{text}'; {help}");
        }
        return Rule(weekdays=sorted({CODES.index(d) for d in days}), until=until);
    }
    raise ValueError(f"Unknown recurrence '{text}'; {help}");
}

"""Due datetimes of the occurrences AFTER `first_due`, up to `horizon`.
Each keeps the first due's local wall-clock time (e.g. always 5pm), even
across daylight-saving changes."""
def next_dues(rule_text: str, first_due: datetime, horizon: datetime, tz_name: str) -> list[datetime] {
    rule = parse_rule(rule_text);
    tz = zone(tz_name);
    local_first = first_due.astimezone(tz);
    wall = local_first.time();
    out: list[datetime] = [];
    day = local_first.date() + timedelta(days=1);
    while True {
        due = datetime.combine(day, wall, tzinfo=tz);
        if due > horizon or (rule.until is not None and day > rule.until) {
            break;
        }
        if day.weekday() in rule.weekdays {
            out.append(due);
        }
        day = day + timedelta(days=1);
    }
    return out;
}
