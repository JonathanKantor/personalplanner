"""Demo data so the planner can be shown without a Google account.

Dates are relative to "now", so the demo always looks like this week.
Re-running replaces the previous demo tasks (anything with is_demo=True) and
re-imports the demo calendars (upsert, so no duplicates). Your own tasks and
calendars are left alone.

The demo classes are generated as real .ics text and imported through the
same code path as an uploaded file, so the demo exercises the real sync code.
"""

import from datetime { datetime, timedelta }
import from core.models { Task, Priority, SyncResult }
import from core.timeutil { now_utc, to_iso, zone, week_start }
import from core.preferences { _prefs }
import from core.calendars { _get_or_create_calendar, _sync_ics_text, _refresh_class_flags }

"""One demo task: due `days` from today at `hour` o'clock local time."""
obj DemoTask {
    has title: str, days: int, hour: int, priority: Priority, minutes: int, course: str;
}

glob DEMO_TASKS: list[DemoTask] = [
    DemoTask(title="Problem set 4", days=2, hour=23, priority=Priority.HIGH, minutes=180, course="EECS 376"),
    DemoTask(title="Read chapter 7", days=1, hour=10, priority=Priority.MEDIUM, minutes=60, course="PSYCH 111"),
    DemoTask(title="Project milestone writeup", days=4, hour=17, priority=Priority.HIGH, minutes=240, course="EECS 449"),
    DemoTask(title="Lab report draft", days=3, hour=23, priority=Priority.MEDIUM, minutes=120, course="PHYSICS 240"),
    DemoTask(title="Review lecture notes", days=5, hour=12, priority=Priority.LOW, minutes=45, course="EECS 376"),
    DemoTask(title="Email advisor about schedule", days=1, hour=17, priority=Priority.LOW, minutes=15, course="")
];

"""A weekly event on `days` (0=Mon..6=Sun) from `start` to `end` local time."""
obj DemoWeekly {
    has uid: str, title: str, days: list[int], start: str, end: str;
}

glob DAY_CODES: list[str] = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"];

# Note EECS 449 ends at 13:30 and PSYCH 111 Discussion starts at 13:30 on
# Tuesday: back-to-back classes, a case the scheduler must handle.
glob DEMO_CLASSES: list[DemoWeekly] = [
    DemoWeekly(uid="demo-eecs376-lec", title="EECS 376 Lecture", days=[0, 2], start="10:30", end="12:00"),
    DemoWeekly(uid="demo-eecs376-dis", title="EECS 376 Discussion", days=[4], start="13:30", end="14:30"),
    DemoWeekly(uid="demo-eecs449-lec", title="EECS 449 Lecture", days=[1, 3], start="12:00", end="13:30"),
    DemoWeekly(uid="demo-psych111-dis", title="PSYCH 111 Discussion", days=[1], start="13:30", end="14:30"),
    DemoWeekly(uid="demo-psych111-lec", title="PSYCH 111 Lecture", days=[1, 3], start="09:00", end="10:30"),
    DemoWeekly(uid="demo-phys240-lab", title="PHYSICS 240 Lab", days=[2], start="14:00", end="16:00")
];

glob DEMO_OTHER: list[DemoWeekly] = [
    DemoWeekly(uid="demo-club", title="Robotics club", days=[3], start="19:00", end="20:30")
];

def _ics_stamp(dt: datetime) -> str {
    return dt.strftime("%Y%m%dT%H%M%S");
}

"""Build an .ics calendar of weekly events for 16 weeks starting this Monday."""
def demo_ics(name: str, events: list[DemoWeekly], tz: str, monday: datetime, extra: str = "") -> str {
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//jac-planner//demo//EN", f"X-WR-CALNAME:{name}"];
    for ev in events {
        first = monday + timedelta(days=ev.days[0]);   # first occurrence day
        (sh, sm) = [int(x) for x in ev.start.split(":")];
        (eh, em) = [int(x) for x in ev.end.split(":")];
        start = first.replace(hour=sh, minute=sm);
        end = first.replace(hour=eh, minute=em);
        byday = ",".join([DAY_CODES[d] for d in ev.days]);
        lines += [
            "BEGIN:VEVENT",
            f"UID:{ev.uid}",
            f"SUMMARY:{ev.title}",
            f"DTSTART;TZID={tz}:{_ics_stamp(start)}",
            f"DTEND;TZID={tz}:{_ics_stamp(end)}",
            f"RRULE:FREQ=WEEKLY;BYDAY={byday};COUNT={16 * len(ev.days)}",
            "END:VEVENT"
        ];
    }
    if extra {
        lines.append(extra);
    }
    lines.append("END:VCALENDAR");
    return "\r\n".join(lines) + "\r\n";
}

def:protect seed_demo_data -> dict {
    p = _prefs();
    tz = p.timezone;

    # --- tasks: replace previous demo tasks
    old = [t for t in [root -->][?:Task] if t.is_demo];
    removed = len(old);
    for t in old {
        del t;
    }
    today = now_utc().astimezone(zone(tz)).replace(minute=0, second=0, microsecond=0);
    for d in DEMO_TASKS {
        due = (today + timedelta(days=d.days)).replace(hour=d.hour);
        root ++> Task(
            title=d.title,
            due=to_iso(due),
            priority=d.priority,
            estimated_minutes=d.minutes,
            category=d.course,
            created_at=to_iso(now_utc()),
            is_demo=True
        );
    }

    # --- calendars: imported through the normal .ics path
    # On a weekend, demo next week (this week is nearly over).
    monday = week_start(now_utc() + timedelta(days=2), tz).astimezone(zone(tz));
    friday_9am = (monday + timedelta(days=4)).replace(hour=9);
    dentist = "\r\n".join([
        "BEGIN:VEVENT", "UID:demo-dentist", "SUMMARY:Dentist",
        f"DTSTART;TZID={tz}:{_ics_stamp(friday_9am)}",
        f"DTEND;TZID={tz}:{_ics_stamp(friday_9am + timedelta(hours=1))}",
        "END:VEVENT"
    ]);
    classes = _get_or_create_calendar("ics", "demo:classes", "Demo: Classes");
    classes.is_class = True;              # every event in this calendar is a class
    other = _get_or_create_calendar("ics", "demo:personal", "Demo: Personal");
    results: list[SyncResult] = [
        _sync_ics_text(classes, demo_ics("Demo: Classes", DEMO_CLASSES, tz, monday)),
        _sync_ics_text(other, demo_ics("Demo: Personal", DEMO_OTHER, tz, monday, dentist))
    ];
    _refresh_class_flags();
    return {
        "tasks_created": len(DEMO_TASKS),
        "tasks_removed": removed,
        "calendars": [{"calendar": r.calendar, "events": r.total} for r in results]
    };
}
