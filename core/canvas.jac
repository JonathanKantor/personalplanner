"""Import Canvas assignments as tasks from the Canvas calendar feed.

In Canvas: Calendar -> "Calendar Feed" (bottom right) gives a private .ics URL
with every assignment's due date. In that feed:
- an assignment's UID starts with "event-assignment-" (plain calendar events
  such as section meetings have other UIDs and are ignored here);
- its start time is the due time (all-day = due by the end of that day);
- its title ends with the course in brackets: "Essay 2 [ENGLISH 125 004 FA 2026]".

Flow: canvas_sync(url) fetches the feed, refreshes the due date/title of tasks
already imported (estimates are kept), and returns every assignment with a
status. The user picks which to import and sets estimates; canvas_import(...)
creates those tasks. Each task remembers its Canvas UID (Task.source_uid), so
re-syncing never creates duplicates.
"""

import re;                                   # server anchor (see core/tasks.jac) + course parsing
import from datetime { datetime, date, timedelta }
import from core.models { Task, CanvasFeed, CanvasItem, CanvasPreview, CanvasImportResult }
import from core.timeutil { now_utc, to_iso, from_iso, zone }
import from core.preferences { _prefs }
import from core.ics { parse_calendar, normalize_url }
import from core.calendars { _fetch_ics }
import from core.changes { get_int, get_str }
import from core.tasks { _priority, _check_minutes }
import from core.planner { replan_if_pending }

# Assignments due this long ago still show up (as "past_due"); later ones up to
# the horizon. A semester fits in the horizon.
glob PAST_DAYS: int = 14,
     HORIZON_DAYS: int = 180;

"""One assignment read from the feed (before comparing with your tasks)."""
obj Assignment {
    has uid: str, title: str, course: str, due: datetime, url: str;
}

# ------------------------------------------------------------------ parsing (pure)

"""Split "Essay 2 [ENGLISH 125 004 FA 2026]" into ("Essay 2", "ENGLISH 125")."""
def split_course(summary: str) -> tuple[str, str] {
    m = re.search(r"\s*\[([^\]]+)\]\s*$", summary);
    if not m {
        return (summary.strip(), "");
    }
    title = summary[:m.start()].strip();
    full = m.group(1).strip();
    # "EECS 449 001 FA 2026" -> "EECS 449": subject + course number is enough.
    short = re.match(r"^([A-Za-z]+\s*\d{3}[A-Za-z]?)\b", full);
    return (title, short.group(1) if short else full);
}

def _is_assignment(uid: str, url: str) -> bool {
    if uid.startswith("event-assignment-") {
        return True;
    }
    return any(part in url for part in ["/assignments/", "/quizzes/", "/discussion_topics/"]);
}

"""All assignments in a Canvas feed, soonest first. Times are converted to
UTC; an all-day due date means 23:59 local time that day."""
def parse_canvas_feed(text: str, tz_name: str) -> list[Assignment] {
    cal = parse_calendar(text);
    tz = zone(tz_name);
    found: list[Assignment] = [];
    for ev in cal.walk("VEVENT") {
        uid = str(ev.get("UID", ""));
        url = str(ev.get("URL", ""));
        if not _is_assignment(uid, url) or "DTSTART" not in ev {
            continue;
        }
        raw = ev["DTSTART"].dt;
        if isinstance(raw, datetime) {
            due = raw if raw.tzinfo else raw.replace(tzinfo=tz);
        } else {
            due = datetime(raw.year, raw.month, raw.day, 23, 59, tzinfo=tz);
        }
        (title, course) = split_course(str(ev.get("SUMMARY", "(untitled)")));
        found.append(Assignment(uid=uid, title=title, course=course, due=due, url=url));
    }
    found.sort(key=lambda (a: Assignment) { (a.due, a.title); });
    return found;
}

# ------------------------------------------------------------------ helpers

def _feed -> CanvasFeed | None {
    feeds = [root -->][?:CanvasFeed];
    return feeds[0] if feeds else None;
}

def _imported -> dict[str, Task] {
    return {t.source_uid: t for t in [root -->][?:Task] if t.source_uid};
}

"""Fetch the feed (saved URL if `url` is empty) and return its assignments
inside the time window, plus the feed node (created/updated)."""
def _load(url: str) -> tuple[CanvasFeed, list[Assignment]] {
    feed = _feed();
    if url.strip() {
        url = normalize_url(url);
        if feed is None {
            feed = root ++> CanvasFeed(url=url);
        } else {
            feed.url = url;
        }
    } elif feed is None {
        raise ValueError("Paste your Canvas calendar feed URL first (Canvas: Calendar -> Calendar Feed)");
    }
    text = _fetch_ics(feed.url);
    items = parse_canvas_feed(text, _prefs().timezone);
    if not items and "BEGIN:VCALENDAR" in text {
        raise ValueError("No assignments found in that feed. Is it the Canvas Calendar Feed URL?");
    }
    now = now_utc();
    lo = now - timedelta(days=PAST_DAYS);
    hi = now + timedelta(days=HORIZON_DAYS);
    feed.last_synced = to_iso(now);
    return (feed, [a for a in items if lo <= a.due and a.due <= hi]);
}

# ------------------------------------------------------------------ endpoints

"""Fetch the Canvas feed. Updates tasks already imported from it (due date and
title only; your estimates are kept) and lists every assignment with a status:
"new", "imported", "dismissed" (you chose not to import it) or "past_due"."""
def:protect canvas_sync(url: str = "") -> CanvasPreview {
    (feed, assignments) = _load(url);
    imported = _imported();
    now = now_utc();
    updated = 0;
    items: list[CanvasItem] = [];
    for a in assignments {
        task = imported.get(a.uid);
        if task is not None {
            # Canvas is the source of truth for due date and title.
            if task.due != to_iso(a.due) or task.title != a.title {
                task.due = to_iso(a.due);
                task.title = a.title;
                updated += 1;
            }
            status = "imported";
        } elif a.due < now {
            status = "past_due";
        } elif a.uid in feed.dismissed {
            status = "dismissed";
        } else {
            status = "new";
        }
        items.append(CanvasItem(
            uid=a.uid, title=a.title, course=a.course, due=to_iso(a.due), url=a.url, status=status
        ));
    }
    if updated {
        replan_if_pending();
    }
    return CanvasPreview(
        feed_url=feed.url, items=items, updated=updated,
        courses=sorted({a.course for a in assignments if a.course})
    );
}

"""Create tasks for the chosen assignments. `choices` has one entry per
assignment shown, e.g. {"uid": "...", "include": true, "estimated_minutes": 90,
"priority": "high", "title": "...", "course": "..."}. Unchosen ones
(include=false) are remembered as dismissed. Due dates come from the feed."""
def:protect canvas_import(choices: list[dict]) -> CanvasImportResult {
    (feed, assignments) = _load("");
    by_uid: dict[str, Assignment] = {a.uid: a for a in assignments};
    imported = _imported();
    result = CanvasImportResult();
    # Validate every row before creating anything.
    rows: list[tuple[Assignment, dict]] = [];
    for c in choices {
        uid = get_str(c, "uid", "");
        if uid not in by_uid {
            raise ValueError(f"Unknown or out-of-range Canvas assignment {uid}; sync again");
        }
        if c.get("include") {
            _ = _check_minutes(get_int(c, "estimated_minutes", 60));
            _ = _priority(get_str(c, "priority", "medium"));
        }
        rows.append((by_uid[uid], c));
    }
    dismissed = list(feed.dismissed);
    for (a, c) in rows {
        if a.uid in imported {
            result.skipped += 1;
            continue;
        }
        if not c.get("include") {
            if a.uid not in dismissed {
                dismissed.append(a.uid);
            }
            result.dismissed += 1;
            continue;
        }
        title = get_str(c, "title", a.title).strip() or a.title;
        root ++> Task(
            title=title,
            due=to_iso(a.due),
            priority=_priority(get_str(c, "priority", "medium")),
            estimated_minutes=_check_minutes(get_int(c, "estimated_minutes", 60)),
            category=get_str(c, "course", a.course).strip(),
            created_at=to_iso(now_utc()),
            source_uid=a.uid,
            source_url=a.url
        );
        dismissed = [d for d in dismissed if d != a.uid];
        result.created += 1;
    }
    feed.dismissed = dismissed;                  # rebind so the change is saved
    replan_if_pending();
    return result;
}

"""The saved feed URL ("" if none), so the page can pre-fill it."""
def:protect canvas_feed_url -> str {
    feed = _feed();
    return feed.url if feed else "";
}

"""Forget the saved feed URL. Imported tasks stay."""
def:protect canvas_forget -> bool {
    for f in [root -->][?:CanvasFeed] {
        del f;
    }
    return True;
}
