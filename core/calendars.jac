"""Calendar storage, sync, and endpoints.

Every source (.ics upload, .ics URL, Google) produces a list of Occurrence
objects and hands it to `_apply_sync`, which is the single place events are
written. That is the "same sync interface" for every source.

Graph shape (per user):
    root --> Calendar --InCalendar--> CalendarEvent (one per occurrence)
    root --> ClassSeries              (recurring series marked as classes)
"""

import requests;
import from datetime { datetime, timedelta }
import from core.models {
    Calendar, CalendarEvent, ClassSeries, InCalendar, Occurrence, SyncResult,
    CalendarView, EventView, SeriesView
}
import from core.timeutil { now_utc, to_iso, from_iso, zone, week_start }
import from core.preferences { _prefs }
import from core.ics { parse_calendar, calendar_name, expand_occurrences, normalize_url }

# Events are synced for this window around today. 120 days ahead covers a
# semester; older events are kept only a week back.
glob SYNC_DAYS_BACK: int = 7,
     SYNC_DAYS_AHEAD: int = 120;

def sync_window -> tuple[datetime, datetime] {
    now = now_utc();
    return (now - timedelta(days=SYNC_DAYS_BACK), now + timedelta(days=SYNC_DAYS_AHEAD));
}

# ------------------------------------------------------------------ helpers

def _calendars -> list[Calendar] {
    return [root -->][?:Calendar];
}

"""Events of one calendar. `->:InCalendar:->` follows only InCalendar edges."""
def _events(cal: Calendar) -> list[CalendarEvent] {
    return [cal ->:InCalendar:->][?:CalendarEvent];
}

def _find_calendar(id: str) -> Calendar {
    for c in _calendars() {
        if jid(c) == id {
            return c;
        }
    }
    raise ValueError(f"No calendar with id {id}");
}

"""Find the calendar for a source, or create it the first time."""
def _get_or_create_calendar(source: str, external_id: str, name: str) -> Calendar {
    for c in _calendars() {
        if c.source == source and c.external_id == external_id {
            if name {
                c.name = name;
            }
            return c;
        }
    }
    return root ++> Calendar(source=source, external_id=external_id, name=name);
}

def _class_series_ids -> set[str] {
    return {s.series_id for s in [root -->][?:ClassSeries]};
}

"""Recompute is_class for every stored event (after a class flag changes)."""
def _refresh_class_flags -> None {
    marked = _class_series_ids();
    for c in _calendars() {
        for e in _events(c) {
            e.is_class = c.is_class or (e.series_id != "" and e.series_id in marked);
        }
    }
}

"""Store a source's occurrences for `cal`. Upserts by external_id, so
re-syncing updates rather than duplicates; occurrences inside the window that
the source no longer has (cancelled or moved) are removed."""
def _apply_sync(
    cal: Calendar, occurrences: list[Occurrence], window_start: datetime, window_end: datetime
) -> SyncResult {
    result = SyncResult(calendar=cal.name or cal.external_id);
    existing: dict[str, CalendarEvent] = {e.external_id: e for e in _events(cal)};
    marked = _class_series_ids();
    synced_at = to_iso(now_utc());
    seen: set[str] = set();

    for occ in occurrences {
        if occ.external_id in seen {
            continue;                       # defensive: source listed it twice
        }
        seen.add(occ.external_id);
        ev = existing.get(occ.external_id);
        if ev is None {
            ev = CalendarEvent(external_id=occ.external_id);
            # `+>:InCalendar:+>` connects with a typed edge; since `cal` is
            # attached to root, the new event is persisted too.
            cal +>:InCalendar:+> ev;
            result.added += 1;
        } elif (ev.title, ev.start, ev.end, ev.all_day) != (occ.title, occ.start, occ.end, occ.all_day) {
            result.updated += 1;
        }
        ev.series_id = occ.series_id;
        ev.title = occ.title;
        ev.start = occ.start;
        ev.end = occ.end;
        ev.all_day = occ.all_day;
        ev.is_class = cal.is_class or (occ.series_id != "" and occ.series_id in marked);
        ev.last_synced = synced_at;
    }

    # Anything in the window that the source no longer lists is gone.
    for (ext_id, ev) in existing.items() {
        if ext_id in seen {
            continue;
        }
        start = from_iso(ev.start);
        if window_start <= start and start < window_end {
            del ev;
            result.removed += 1;
        }
    }
    cal.last_synced = synced_at;
    result.total = len(_events(cal));
    return result;
}

def _sync_ics_text(cal: Calendar, text: str) -> SyncResult {
    parsed = parse_calendar(text);
    if not cal.name {
        cal.name = calendar_name(parsed, "Imported calendar");
    }
    (start, end) = sync_window();
    return _apply_sync(cal, expand_occurrences(parsed, start, end, _prefs().timezone), start, end);
}

def _fetch_ics(url: str) -> str {
    try {
        resp = requests.get(url, timeout=20);
        resp.raise_for_status();
    } except requests.RequestException as e {
        raise ValueError(f"Could not download calendar: {str(e)}");
    }
    return resp.text;
}

def _view(c: Calendar) -> CalendarView {
    return CalendarView(
        id=jid(c), source=c.source, name=c.name, is_class=c.is_class,
        last_synced=c.last_synced, event_count=len(_events(c))
    );
}

def _event_view(c: Calendar, e: CalendarEvent) -> EventView {
    return EventView(
        id=jid(e), calendar_id=jid(c), series_id=e.series_id, title=e.title,
        start=e.start, end=e.end, all_day=e.all_day, is_class=e.is_class,
        editable=c.source == "manual"
    );
}

"""All stored events overlapping [start, end), soonest first. Used by the
scheduler and the week/today views."""
def events_between(start: datetime, end: datetime) -> list[EventView] {
    out: list[EventView] = [];
    for c in _calendars() {
        for e in _events(c) {
            if from_iso(e.start) < end and from_iso(e.end) > start {
                out.append(_event_view(c, e));
            }
        }
    }
    out.sort(key=lambda (v: EventView) { v.start; });
    return out;
}

# ------------------------------------------------------------------ endpoints

"""Import an .ics file's contents. Re-importing under the same name updates
that calendar instead of creating a second one."""
def:protect import_ics(content: str, name: str = "") -> SyncResult {
    if not content.strip() {
        raise ValueError("The .ics file is empty");
    }
    parsed_name = calendar_name(parse_calendar(content), "Imported calendar");
    label = name.strip() or parsed_name;
    cal = _get_or_create_calendar("ics", f"upload:{label}", label);
    return _sync_ics_text(cal, content);
}

"""Subscribe to a calendar's private iCal URL (e.g. Google's "Secret address
in iCal format"). The URL is remembered so sync_calendar can re-fetch it."""
def:protect import_ics_url(url: str, name: str = "") -> SyncResult {
    url = normalize_url(url);
    text = _fetch_ics(url);
    cal = _get_or_create_calendar("ics", url, name.strip());
    return _sync_ics_text(cal, text);
}

def:protect list_calendars -> list[CalendarView] {
    return [_view(c) for c in _calendars()];
}

"""Mark a whole calendar (e.g. "Classes") as class time."""
def:protect set_calendar_is_class(calendar_id: str, is_class: bool) -> CalendarView {
    c = _find_calendar(calendar_id);
    c.is_class = is_class;
    _refresh_class_flags();
    return _view(c);
}

"""Recurring series across all calendars, so individual ones can be marked as classes."""
def:protect list_series -> list[SeriesView] {
    marked = _class_series_ids();
    found: dict[str, SeriesView] = {};
    for c in _calendars() {
        for e in _events(c) {
            if not e.series_id {
                continue;
            }
            if c.source == "manual" and e.series_id.startswith("one-") {
                continue;                        # your one-off events aren't "recurring"
            }
            if e.series_id not in found {
                found[e.series_id] = SeriesView(
                    series_id=e.series_id, title=e.title, calendar=c.name,
                    occurrences=0, is_class=c.is_class or e.series_id in marked
                );
            }
            found[e.series_id].occurrences += 1;
        }
    }
    series = list(found.values());
    series.sort(key=lambda (s: SeriesView) { s.title.lower(); });
    return series;
}

"""Mark one recurring series (e.g. "EECS 376 Lecture") as a class, or unmark it."""
def:protect set_series_is_class(series_id: str, is_class: bool) -> bool {
    existing = [s for s in [root -->][?:ClassSeries] if s.series_id == series_id];
    if is_class and not existing {
        root ++> ClassSeries(series_id=series_id);
    }
    if not is_class {
        for s in existing {
            del s;
        }
    }
    _refresh_class_flags();
    return is_class;
}

"""Events in a date range. Dates are local (YYYY-MM-DD); end is exclusive.
With no arguments, returns the current week (Monday to Monday)."""
def:protect list_events(start: str = "", end: str = "") -> list[EventView] {
    tz = _prefs().timezone;
    if start {
        s = datetime.fromisoformat(start).replace(tzinfo=zone(tz));
    } else {
        s = week_start(now_utc(), tz);
    }
    if end {
        e = datetime.fromisoformat(end).replace(tzinfo=zone(tz));
    } else {
        e = s + timedelta(days=7);
    }
    if e <= s {
        raise ValueError("end must be after start");
    }
    return events_between(s, e);
}

"""Remove a calendar and all its events from the planner (not from Google)."""
def:protect delete_calendar(calendar_id: str) -> bool {
    c = _find_calendar(calendar_id);
    for e in _events(c) {
        del e;
    }
    del c;
    return True;
}
