"""Planning endpoints: run the scheduler on the user's data, and manage the
suggested blocks (accept / reject / adjust), plus the agenda and progress views.

Graph shape:  root --> Task --ScheduledAs--> TimeBlock
A block is stored because its task is connected to root.

Re-planning rule: suggest_schedule throws away the old SUGGESTED blocks and
plans again, but ACCEPTED blocks are fixed - they count as busy time - and
REJECTED blocks are remembered so the same slot isn't offered for that task
again.
"""

import from datetime { datetime, date, timedelta }
import from core.models {
    Task, TaskStatus, TimeBlock, BlockStatus, ScheduledAs, Preferences,
    BlockView, UnscheduledView, PlanView, AgendaView, ProgressView, EventView, TaskView
}
import from core.timeutil { now_utc, to_iso, from_iso, zone, week_start, parse_due }
import from core.preferences { _prefs }
import from core.calendars { events_between }
import from core.recurrence { next_dues }
import from core.scheduler { plan, Interval, SchedPrefs, SchedTask }
import from core.changes { as_int }

glob DEFAULT_DAYS: int = 7,
     MAX_DAYS: int = 28;

# ------------------------------------------------------------------ helpers

def _tasks -> list[Task] {
    return [root -->][?:Task];
}

"""A task's blocks: follow its outgoing ScheduledAs edges."""
def _blocks(t: Task) -> list[TimeBlock] {
    return [t ->:ScheduledAs:->][?:TimeBlock];
}

def _minutes(b: TimeBlock) -> int {
    return int((from_iso(b.end) - from_iso(b.start)).total_seconds() // 60);
}

def _view(t: Task, b: TimeBlock) -> BlockView {
    return BlockView(
        id=jid(b), task_id=jid(t), task_title=t.title, category=t.category,
        priority=str(t.priority), start=b.start, end=b.end, status=str(b.status),
        reason=b.reason, session=b.session, sessions_total=b.sessions_total
    );
}

"""Find one of the caller's blocks (and its task) by id."""
def _find_block(id: str) -> tuple[Task, TimeBlock] {
    for t in _tasks() {
        for b in _blocks(t) {
            if jid(b) == id {
                return (t, b);
            }
        }
    }
    raise ValueError(f"No block with id {id}");
}

def _sched_prefs(p: Preferences) -> SchedPrefs {
    return SchedPrefs(
        tz=p.timezone, work_start=p.work_start, work_end=p.work_end,
        days_off=p.days_off, preferred_start=p.preferred_start,
        preferred_end=p.preferred_end, min_break_minutes=p.min_break_minutes,
        max_focus_minutes_per_day=p.max_focus_minutes_per_day
    );
}

"""Now, rounded up to the next quarter hour, so suggestions start on :00/:15/:30/:45."""
def _plan_start -> datetime {
    now = now_utc().replace(second=0, microsecond=0);
    extra = (15 - now.minute % 15) % 15;
    return now + timedelta(minutes=extra);
}

"""Create upcoming occurrences of recurring tasks (up to `horizon`)."""
def _expand_recurring(horizon: datetime, tz: str) -> None {
    tasks = _tasks();
    for template in tasks {
        if not template.recurrence or template.parent_id {
            continue;
        }
        tid = jid(template);
        have = {t.due for t in tasks if t.parent_id == tid};
        for due in next_dues(template.recurrence, from_iso(template.due), horizon, tz) {
            if to_iso(due) not in have {
                root ++> Task(
                    title=template.title, notes=template.notes, due=to_iso(due),
                    priority=template.priority, estimated_minutes=template.estimated_minutes,
                    category=template.category, created_at=to_iso(now_utc()),
                    parent_id=tid, is_demo=template.is_demo
                );
            }
        }
    }
}

def _update_task_status(t: Task) -> None {
    if t.status == TaskStatus.DONE {
        return;
    }
    accepted = sum([_minutes(b) for b in _blocks(t) if b.status == BlockStatus.ACCEPTED]);
    t.status = TaskStatus.SCHEDULED if accepted >= t.estimated_minutes else TaskStatus.TODO;
}

"""Run the scheduler and store its suggestions. Used by suggest_schedule and
whenever tasks or preferences change while suggestions are pending."""
def _replan(days: int) -> PlanView {
    p = _prefs();
    start = _plan_start();
    end = start + timedelta(days=days);
    _expand_recurring(end, p.timezone);

    busy: list[Interval] = [];
    focus_used: dict[date, int] = {};
    sched_tasks: list[SchedTask] = [];
    for t in _tasks() {
        accepted_minutes = 0;
        avoid: list[Interval] = [];
        for b in _blocks(t) {
            span = Interval(start=from_iso(b.start), end=from_iso(b.end));
            if b.status == BlockStatus.SUGGESTED {
                del b;                                   # old suggestions are replaced
            } elif b.status == BlockStatus.ACCEPTED {
                busy.append(span);                       # accepted = fixed
                accepted_minutes += _minutes(b);
                day = span.start.astimezone(zone(p.timezone)).date();
                focus_used[day] = focus_used.get(day, 0) + _minutes(b);
            } else {
                avoid.append(span);                      # rejected: don't offer again
            }
        }
        if t.status != TaskStatus.DONE and t.estimated_minutes > accepted_minutes {
            sched_tasks.append(SchedTask(
                id=jid(t), title=t.title, due=from_iso(t.due), priority=str(t.priority),
                minutes=t.estimated_minutes - accepted_minutes, avoid=avoid
            ));
        }
    }
    for e in events_between(start, end) {
        if not e.all_day {                               # all-day events don't block time
            busy.append(Interval(start=from_iso(e.start), end=from_iso(e.end)));
        }
    }

    result = plan(sched_tasks, _sched_prefs(p), busy, focus_used, Interval(start=start, end=end));

    by_id: dict[str, Task] = {jid(t): t for t in _tasks()};
    suggestions: list[BlockView] = [];
    for pl in result.placements {
        t = by_id[pl.task_id];
        block = TimeBlock(
            start=to_iso(pl.start), end=to_iso(pl.end), reason=pl.reason,
            session=pl.session, sessions_total=pl.sessions_total
        );
        t +>:ScheduledAs:+> block;
        suggestions.append(_view(t, block));
    }
    return PlanView(
        window_start=to_iso(start), window_end=to_iso(end), suggestions=suggestions,
        unscheduled=[
            UnscheduledView(task_id=u.task_id, title=u.title, minutes_needed=u.minutes_needed,
                            minutes_placed=u.minutes_placed, reason=u.reason)
            for u in result.unplaced
        ]
    );
}

"""Called after a task or preference change: if the user has suggestions
waiting, regenerate them so they reflect the change. Accepted blocks are
never touched."""
def replan_if_pending -> None {
    for t in _tasks() {
        for b in _blocks(t) {
            if b.status == BlockStatus.SUGGESTED {
                _replan(DEFAULT_DAYS);
                return;
            }
        }
    }
}

def _range(start: str, days: int, tz: str) -> tuple[datetime, datetime] {
    if start {
        s = datetime.fromisoformat(start).replace(tzinfo=zone(tz));
    } else {
        s = week_start(now_utc(), tz);
    }
    return (s, s + timedelta(days=days));
}

def _agenda(s: datetime, e: datetime, tz: str) -> AgendaView {
    blocks: list[BlockView] = [];
    due: list[TaskView] = [];
    for t in _tasks() {
        for b in _blocks(t) {
            if b.status != BlockStatus.REJECTED and from_iso(b.start) < e and from_iso(b.end) > s {
                blocks.append(_view(t, b));
            }
        }
        if s <= from_iso(t.due) and from_iso(t.due) < e {
            due.append(t.to_view());
        }
    }
    blocks.sort(key=lambda (b: BlockView) { b.start; });
    due.sort(key=lambda (t: TaskView) { t.due; });
    return AgendaView(
        start=to_iso(s), end=to_iso(e), timezone=tz,
        events=events_between(s, e), blocks=blocks, due=due
    );
}

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
