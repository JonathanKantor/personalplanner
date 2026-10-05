"""Your own events (meetings etc. that aren't in Google Calendar).

They are stored exactly like synced events - CalendarEvent nodes - in a
calendar called "My events" (source "manual"), so the scheduler, week view,
mobile app and assistant all treat them as busy time with no extra code.
Unlike synced events they can be edited and deleted, and calendar sync never
touches them.

Every manual event has a series_id: "one-<id>" for a single event, or
"rep-<id>" shared by the occurrences of a weekly repeat. That lets "counts as
a class" use the normal class-series marking (ClassSeries), which survives
the class-flag refresh.
"""

import uuid;                                 # server anchor (see core/tasks.jac) + unique ids
import from datetime { datetime, date, timedelta }
import from core.models {
    Calendar, CalendarEvent, ClassSeries, InCalendar, EventView, BlockStatus
}
import from core.timeutil { to_iso, from_iso, zone, parse_hhmm, now_utc }
import from core.preferences { _prefs }
import from core.calendars {
    _get_or_create_calendar, _events, _event_view, _refresh_class_flags
}
import from core.planner { replan_if_pending, _tasks, _blocks }
import from core.changes { as_int, check_keys, get_str }

glob MAX_WEEKS: int = 30;

obj EventResult {
    has events: list[EventView],
        conflicts: list[str];                # planned blocks the event now overlaps
}

# ------------------------------------------------------------------ helpers

def _my_calendar -> Calendar {
    return _get_or_create_calendar("manual", "manual:events", "My events");
}

def _find(id: str) -> CalendarEvent {
    for e in _events(_my_calendar()) {
        if jid(e) == id {
            return e;
        }
    }
    raise ValueError("That event can't be found (only your own events can be edited)");
}

"""Local date + "HH:MM" start/end -> aware datetimes; validates the order."""
def _span(day: str, start: str, end: str) -> tuple[datetime, datetime] {
    tz = zone(_prefs().timezone);
    try {
        d = date.fromisoformat(day);
    } except ValueError {
        raise ValueError(f"Date must be YYYY-MM-DD (got '{day}')");
    }
    s = datetime.combine(d, parse_hhmm(start), tzinfo=tz);
    e = datetime.combine(d, parse_hhmm(end), tzinfo=tz);
    if e <= s {
        raise ValueError("The end time must be after the start time");
    }
    return (s, e);
}

"""Titles of planned (accepted) blocks overlapping any of the spans."""
def _conflicts(spans: list[tuple[datetime, datetime]]) -> list[str] {
    found: list[str] = [];
    for t in _tasks() {
        for b in _blocks(t) {
            if b.status != BlockStatus.ACCEPTED {
                continue;
            }
            bs = from_iso(b.start);
            be = from_iso(b.end);
            for (s, e) in spans {
                if bs < e and s < be {
                    found.append(f"{t.title} ({bs.astimezone(s.tzinfo).strftime('%a %H:%M')})");
                    break;
                }
            }
        }
    }
    return found;
}

def _set_class(series_id: str, is_class: bool) -> None {
    existing = [c for c in [root -->][?:ClassSeries] if c.series_id == series_id];
    if is_class and not existing {
        root ++> ClassSeries(series_id=series_id);
    }
    if not is_class {
        for c in existing {
            del c;
        }
    }
}

def _result(cal: Calendar, events: list[CalendarEvent], spans: list[tuple[datetime, datetime]]) -> EventResult {
    replan_if_pending();                     # pending suggestions move out of the way
    return EventResult(events=[_event_view(cal, e) for e in events], conflicts=_conflicts(spans));
}

# ------------------------------------------------------------------ endpoints

"""Add an event on `day` (local YYYY-MM-DD) from `start` to `end` ("HH:MM").
repeat_weeks > 1 repeats it weekly that many times (including the first)."""
def:protect create_event(
    title: str, day: str, start: str, end: str, is_class: bool, repeat_weeks: int = 1
) -> EventResult {
    title = title.strip();
    if not title {
        raise ValueError("Give the event a title");
    }
    weeks = as_int(repeat_weeks, "repeat_weeks");           # see core/changes.jac
    if weeks < 1 or weeks > MAX_WEEKS {
        raise ValueError(f"Repeat for 1 to {MAX_WEEKS} weeks");
    }
    (s, e) = _span(day, start, end);
    cal = _my_calendar();
    key = uuid.uuid4().hex[:12];
    series = ("rep-" if weeks > 1 else "one-") + key;
    created: list[CalendarEvent] = [];
    spans: list[tuple[datetime, datetime]] = [];
    for i in range(weeks) {
        # Same wall-clock time each week, even across daylight-saving changes.
        d = s.date() + timedelta(weeks=i);
        ws = datetime.combine(d, s.timetz());
        we = datetime.combine(d, e.timetz());
        ev = CalendarEvent(
            external_id=f"manual-{key}@{to_iso(ws)}", series_id=series, title=title,
            start=to_iso(ws), end=to_iso(we), last_synced=to_iso(now_utc())
        );
        cal +>:InCalendar:+> ev;
        created.append(ev);
        spans.append((ws, we));
    }
    _set_class(series, bool(is_class));
    _refresh_class_flags();
    return _result(cal, created, spans);
}

"""Change one occurrence: changes may hold "title", "day", "start", "end"
(local date / HH:MM). Used by the edit dialog and by dragging."""
def:protect update_event(id: str, changes: dict) -> EventResult {
    check_keys(changes, ["title", "day", "start", "end"]);
    ev = _find(id);
    tz = zone(_prefs().timezone);
    cur_s = from_iso(ev.start).astimezone(tz);
    cur_e = from_iso(ev.end).astimezone(tz);
    title = get_str(changes, "title", ev.title).strip();
    if not title {
        raise ValueError("Give the event a title");
    }
    (s, e) = _span(
        get_str(changes, "day", cur_s.date().isoformat()),
        get_str(changes, "start", cur_s.strftime("%H:%M")),
        get_str(changes, "end", cur_e.strftime("%H:%M"))
    );
    ev.title = title;
    ev.start = to_iso(s);
    ev.end = to_iso(e);
    return _result(_my_calendar(), [ev], [(s, e)]);
}

"""Delete one of your events; whole_series=True deletes every week of a repeat.
Returns how many occurrences were removed."""
def:protect delete_event(id: str, whole_series: bool) -> int {
    ev = _find(id);
    targets = [ev];
    if whole_series {
        targets = [e for e in _events(_my_calendar()) if e.series_id == ev.series_id];
    }
    series = ev.series_id;
    count = len(targets);
    for e in targets {
        del e;
    }
    if not [e for e in _events(_my_calendar()) if e.series_id == series] {
        _set_class(series, False);           # nothing left in the series
    }
    replan_if_pending();
    return count;
}
