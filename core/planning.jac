"""Planning endpoints: suggest a schedule, accept / reject / adjust suggested
blocks, and the agenda, today and progress views. The logic lives in
core/planner.jac (see the note there on why the two are separate).
"""

import from datetime { datetime, timedelta }
import from core.models {
    TaskStatus, BlockStatus, BlockView, PlanView, AgendaView, ProgressView
}
import from core.timeutil { now_utc, to_iso, from_iso, zone, week_start, parse_due }
import from core.preferences { _prefs }
import from core.calendars { events_between }
import from core.changes { as_int }
import from core.planner {
    _tasks, _blocks, _minutes, _view, _find_block, _update_task_status, _replan,
    _range, _agenda
}

glob MAX_DAYS: int = 28;

# ------------------------------------------------------------------ endpoints

"""Plan the next `days` days (default 7, max 28). Returns the new suggestions
and anything that couldn't fit, with reasons."""
def:protect suggest_schedule(days: int = 7) -> PlanView {
    days = as_int(days, "days");          # see core/changes.jac
    if days < 1 or days > MAX_DAYS {
        raise ValueError(f"days must be between 1 and {MAX_DAYS}");
    }
    return _replan(days);
}

"""Blocks overlapping a range. `status` filters ("suggested", "accepted",
"rejected"); "" means suggested + accepted."""
def:protect list_blocks(start: str = "", days: int = 7, status: str = "") -> list[BlockView] {
    days = as_int(days, "days");
    tz = _prefs().timezone;
    (s, e) = _range(start, days, tz);
    out: list[BlockView] = [];
    for t in _tasks() {
        for b in _blocks(t) {
            wanted = str(b.status) == status if status else b.status != BlockStatus.REJECTED;
            if wanted and from_iso(b.start) < e and from_iso(b.end) > s {
                out.append(_view(t, b));
            }
        }
    }
    out.sort(key=lambda (b: BlockView) { b.start; });
    return out;
}

def:protect accept_block(id: str) -> BlockView {
    (t, b) = _find_block(id);
    b.status = BlockStatus.ACCEPTED;
    _update_task_status(t);
    return _view(t, b);
}

def:protect reject_block(id: str) -> BlockView {
    (t, b) = _find_block(id);
    b.status = BlockStatus.REJECTED;
    _update_task_status(t);
    return _view(t, b);
}

def:protect accept_all -> list[BlockView] {
    out: list[BlockView] = [];
    for t in _tasks() {
        for b in _blocks(t) {
            if b.status == BlockStatus.SUGGESTED {
                b.status = BlockStatus.ACCEPTED;
                out.append(_view(t, b));
            }
        }
        _update_task_status(t);
    }
    out.sort(key=lambda (b: BlockView) { b.start; });
    return out;
}

"""Move/resize a block (local times, e.g. "2026-10-20T15:00"). Adjusting a
block also accepts it. Refuses times that overlap calendar events or your
other accepted blocks."""
def:protect adjust_block(id: str, start: str, end: str) -> BlockView {
    (t, b) = _find_block(id);
    tz = _prefs().timezone;
    s = from_iso(parse_due(start, tz));
    e = from_iso(parse_due(end, tz));
    if e <= s {
        raise ValueError("end must be after start");
    }
    for ev in events_between(s, e) {
        if not ev.all_day {
            raise ValueError(f"That overlaps '{ev.title}'");
        }
    }
    for other_t in _tasks() {
        for other in _blocks(other_t) {
            if other is not b and other.status == BlockStatus.ACCEPTED
                and from_iso(other.start) < e and from_iso(other.end) > s {
                raise ValueError(f"That overlaps your block for '{other_t.title}'");
            }
        }
    }
    b.start = to_iso(s);
    b.end = to_iso(e);
    b.status = BlockStatus.ACCEPTED;
    b.reason = "Adjusted by you";
    _update_task_status(t);
    return _view(t, b);
}

"""Events, planned blocks, and due tasks for `days` days from `start`
(local date YYYY-MM-DD; default this Monday)."""
def:protect get_agenda(start: str = "", days: int = 7) -> AgendaView {
    days = as_int(days, "days");
    if days < 1 or days > 31 {
        raise ValueError("days must be between 1 and 31");
    }
    tz = _prefs().timezone;
    (s, e) = _range(start, days, tz);
    return _agenda(s, e, tz);
}

def:protect get_today -> AgendaView {
    tz = _prefs().timezone;
    s = now_utc().astimezone(zone(tz)).replace(hour=0, minute=0, second=0, microsecond=0);
    return _agenda(s, s + timedelta(days=1), tz);
}

"""This week's numbers (Monday to Monday, local)."""
def:protect get_progress -> ProgressView {
    tz = _prefs().timezone;
    s = week_start(now_utc(), tz);
    e = s + timedelta(days=7);
    now = now_utc();
    done = 0;
    open_count = 0;
    overdue = 0;
    planned = 0;
    completed = 0;
    for t in _tasks() {
        if t.status == TaskStatus.DONE {
            if t.completed_at and s <= from_iso(t.completed_at) and from_iso(t.completed_at) < e {
                done += 1;
            }
        } else {
            open_count += 1;
            if from_iso(t.due) < now {
                overdue += 1;
            }
        }
        for b in _blocks(t) {
            if b.status == BlockStatus.ACCEPTED and s <= from_iso(b.start) and from_iso(b.start) < e {
                planned += _minutes(b);
                if t.status == TaskStatus.DONE {
                    completed += _minutes(b);
                }
            }
        }
    }
    return ProgressView(
        week_start=to_iso(s), tasks_done=done, tasks_open=open_count, tasks_overdue=overdue,
        minutes_planned=planned, minutes_completed=completed
    );
}
