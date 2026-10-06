"""Planning engine glue: runs the scheduler on the user's stored data.

Graph shape:  root --> Task --ScheduledAs--> TimeBlock
A block is stored because its task is connected to root.

Re-planning rule: _replan throws away the old SUGGESTED blocks and plans
again, but ACCEPTED blocks are fixed - they count as busy time - and REJECTED
blocks are remembered so the same slot isn't offered for that task again.

Kept separate from core/planning.jac so that module holds only the HTTP
endpoints, and other server modules (tasks, preferences, views) import the
engine from here rather than from an endpoint module.
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

glob DEFAULT_DAYS: int = 21;         # 3 weeks: work is placed in each task's due week

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
