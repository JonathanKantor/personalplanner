"""Ready-to-draw calendar views for the web and mobile clients.

The clients stay thin: they don't do timezone math. The server converts every
event and block to the user's timezone and returns, per day, items with
display labels ("2:30pm") and minute offsets from local midnight (for
positioning in a grid).
"""

import from datetime { datetime, date, timedelta }
import from core.models { DayItem, DayView, WeekView, TaskView, Preferences, UpcomingItem, ComingUpView, TaskStatus }
import from core.changes { as_int }
import from core.timeutil { now_utc, from_iso, zone, parse_hhmm, week_start }
import from core.preferences { _prefs }
import from core.scheduler { clock }
import from core.planner { _agenda, _tasks }
import from core.models { Task }

def _minutes(dt: datetime) -> int {
    return dt.hour * 60 + dt.minute;
}

def _hhmm_minutes(s: str) -> int {
    t = parse_hhmm(s);
    return t.hour * 60 + t.minute;
}

"""Build DayViews for `days` consecutive local days starting at `first`."""
def _days(first: date, days: int, p: Preferences) -> list[DayView] {
    tz = zone(p.timezone);
    start = datetime.combine(first, datetime.min.time(), tzinfo=tz);
    end = start + timedelta(days=days);
    agenda = _agenda(start, end, p.timezone);
    today = now_utc().astimezone(tz).date();

    by_day: dict[date, list[DayItem]] = {first + timedelta(days=i): [] for i in range(days)};
    due_by_day: dict[date, list[TaskView]] = {d: [] for d in by_day};

    # Task details for blocks and deadlines (course, due weekday, done).
    tasks = {jid(t): t for t in _tasks()};

    def add(kind: str, id: str, title: str, s_iso: str, e_iso: str, all_day: bool,
            status: str = "", reason: str = "", task_id: str = "", editable: bool = False) -> None {
        course = "";
        due_day = "";
        done = False;
        if task_id in tasks {
            t = tasks[task_id];
            course = t.category;
            due_day = from_iso(t.due).astimezone(tz).strftime("%a");
            done = str(t.status) == "done";
        }
        s = from_iso(s_iso).astimezone(tz);
        e = from_iso(e_iso).astimezone(tz);
        day = s.date();
        # An event that runs past midnight is cut at the end of its first day.
        end_min = _minutes(e) if e.date() == day else 24 * 60;
        if day in by_day {
            by_day[day] = by_day[day] + [DayItem(
                id=id, kind=kind, title=title, all_day=all_day,
                start_label="all day" if all_day else clock(s),
                end_label="" if all_day else clock(e),
                start_min=0 if all_day else _minutes(s), end_min=24 * 60 if all_day else end_min,
                status=status, reason=reason, task_id=task_id, editable=editable,
                course=course, due_day=due_day, done=done
            )];
        }
    }

    for ev in agenda.events {
        add("class" if ev.is_class else "event", ev.id, ev.title, ev.start, ev.end, ev.all_day, editable=ev.editable);
    }
    for b in agenda.blocks {
        add("block", b.id, b.task_title, b.start, b.end, False, b.status, b.reason, b.task_id);
    }
    for t in agenda.due {
        d = from_iso(t.due).astimezone(tz).date();
        if d in due_by_day {
            due_by_day[d] = due_by_day[d] + [t];
        }
        # A deadline is a zero-length item at the due time; the web grid draws
        # it as a small coral block ending there.
        add("deadline", "due-" + t.id, t.title, t.due, t.due, False, task_id=t.id);
    }

    out: list[DayView] = [];
    for d in sorted(by_day.keys()) {
        items = sorted(by_day[d], key=lambda (i: DayItem) { (i.start_min, i.end_min); });
        out.append(DayView(
            date=d.isoformat(),
            label=d.strftime("%a %b ") + str(d.day),
            is_today=d == today,
            is_day_off=d.strftime("%a").lower() in p.days_off,
            items=items,
            due=due_by_day[d]
        ));
    }
    return out;
}

"""A week (Monday-Sunday) for the web week view. `start` is any local date in
the wanted week (YYYY-MM-DD); default this week."""
def:protect get_week_view(start: str = "") -> WeekView {
    p = _prefs();
    tz = zone(p.timezone);
    if start {
        anchor = date.fromisoformat(start);
    } else {
        anchor = now_utc().astimezone(tz).date();
    }
    monday = anchor - timedelta(days=anchor.weekday());
    days = _days(monday, 7, p);
    return WeekView(
        start=monday.isoformat(),
        prev_start=(monday - timedelta(days=7)).isoformat(),
        next_start=(monday + timedelta(days=7)).isoformat(),
        label=f"{monday.strftime('%b')} {monday.day} - {(monday + timedelta(days=6)).strftime('%b')} {(monday + timedelta(days=6)).day}",
        timezone=p.timezone,
        work_start_min=_hhmm_minutes(p.work_start),
        work_end_min=_hhmm_minutes(p.work_end),
        days=days,
        suggested_count=sum([len([i for i in d.items if i.status == "suggested"]) for d in days])
    );
}

"""One day for the mobile Today screen. `day` is a local date; default today."""
def:protect get_day_view(day: str = "") -> DayView {
    p = _prefs();
    d = date.fromisoformat(day) if day else now_utc().astimezone(zone(p.timezone)).date();
    return _days(d, 1, p)[0];
}

"""Data for the web "Coming up" card: open tasks soonest first (up to
`limit`), how many are open, and the follow-through score for the week that
contains `week_start` (local YYYY-MM-DD; default this week)."""
def:protect get_coming_up(limit: int = 6, week_start: str = "") -> ComingUpView {
    limit = as_int(limit, "limit");                  # see core/changes.jac
    p = _prefs();
    tz = zone(p.timezone);
    now = now_utc();
    anchor = date.fromisoformat(week_start) if week_start else now.astimezone(tz).date();
    monday = anchor - timedelta(days=anchor.weekday());
    lo = datetime.combine(monday, datetime.min.time(), tzinfo=tz);
    hi = lo + timedelta(days=7);

    tasks = _tasks();
    open_tasks = sorted([t for t in tasks if t.status != TaskStatus.DONE], key=lambda (t: Task) { t.due; });
    items: list[UpcomingItem] = [];
    for t in open_tasks[:max(0, limit)] {
        local = from_iso(t.due).astimezone(tz);
        items.append(UpcomingItem(
            id=jid(t), title=t.title, course=t.category, due=t.due,
            due_day=local.strftime("%a"), date_chip=local.strftime("%b ") + str(local.day),
            overdue=from_iso(t.due) < now
        ));
    }
    in_week = [t for t in tasks if lo <= from_iso(t.due) and from_iso(t.due) < hi];
    return ComingUpView(
        open_count=len(open_tasks), items=items,
        week_done=len([t for t in in_week if t.status == TaskStatus.DONE]),
        week_total=len(in_week)
    );
}

