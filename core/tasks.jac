"""Task endpoints: create, list, update, complete, delete.

All are `def:protect` (login required; see core/preferences.jac); `root` is the caller's own root, so a task
id belonging to someone else is simply "not found".
"""

import from core.models { Task, TaskView, Priority, TaskStatus }
import from core.timeutil { parse_due, to_iso, now_utc }
import from core.preferences { _prefs }
import from core.changes { check_keys, get_str, get_int }

def _view(t: Task) -> TaskView {
    # jid(node) is the node's stable id; it survives restarts and the network.
    return TaskView(
        id=jid(t),
        title=t.title,
        notes=t.notes,
        due=t.due,
        priority=str(t.priority),
        status=str(t.status),
        estimated_minutes=t.estimated_minutes,
        category=t.category,
        recurrence=t.recurrence,
        created_at=t.created_at,
        completed_at=t.completed_at
    );
}

"""Find one of the caller's tasks by id. Only searches this user's root."""
def _find(id: str) -> Task {
    for t in [root -->][?:Task] {
        if jid(t) == id {
            return t;
        }
    }
    raise ValueError(f"No task with id {id}");
}

def _priority(p: str) -> Priority {
    try {
        return Priority(p.strip().lower());
    } except ValueError {
        raise ValueError(f"priority must be low, medium, or high (got '{p}')");
    }
}

def _check_minutes(m: int) -> int {
    if m <= 0 or m > 24 * 60 {
        raise ValueError("estimated_minutes must be between 1 and 1440");
    }
    return m;
}

def:protect create_task(
    title: str,
    due: str,
    priority: str = "medium",
    estimated_minutes: int = 60,
    notes: str = "",
    category: str = "",
    recurrence: str = ""
) -> TaskView {
    if not title.strip() {
        raise ValueError("title is required");
    }
    task = Task(
        title=title.strip(),
        notes=notes,
        due=parse_due(due, _prefs().timezone),
        priority=_priority(priority),
        estimated_minutes=_check_minutes(estimated_minutes),
        category=category.strip(),
        recurrence=recurrence.strip(),
        created_at=to_iso(now_utc())
    );
    root ++> task;                     # attach to the user's root -> persisted
    return _view(task);
}

"""List tasks, soonest due first. `status` filters ("todo", "done", ...); ""
returns everything not done, "all" returns everything."""
def:protect list_tasks(status: str = "") -> list[TaskView] {
    tasks = [root -->][?:Task];
    if status == "" {
        tasks = [t for t in tasks if t.status != TaskStatus.DONE];
    } elif status != "all" {
        tasks = [t for t in tasks if str(t.status) == status];
    }
    tasks.sort(key=lambda (t: Task) { t.due; });
    return [_view(t) for t in tasks];
}

def:protect get_task(id: str) -> TaskView {
    return _view(_find(id));
}

glob TASK_FIELDS: list[str] = [
    "title", "due", "priority", "estimated_minutes", "notes", "category",
    "recurrence", "status"
];

"""Change some of a task's fields, e.g. changes={"due": "2026-10-10", "estimated_minutes": 120}.
Fields not in `changes` keep their value (see core/changes.jac for why a dict)."""
def:protect update_task(id: str, changes: dict) -> TaskView {
    t = _find(id);
    check_keys(changes, TASK_FIELDS);
    # Validate everything before assigning anything, so a bad value changes nothing.
    title = get_str(changes, "title", t.title).strip();
    if not title {
        raise ValueError("title cannot be empty");
    }
    due = parse_due(changes["due"], _prefs().timezone) if "due" in changes else t.due;
    priority = _priority(get_str(changes, "priority", str(t.priority)));
    minutes = _check_minutes(get_int(changes, "estimated_minutes", t.estimated_minutes));
    status = _status(get_str(changes, "status", str(t.status)));

    t.title = title;
    t.due = due;
    t.priority = priority;
    t.estimated_minutes = minutes;
    t.notes = get_str(changes, "notes", t.notes);
    t.category = get_str(changes, "category", t.category).strip();
    t.recurrence = get_str(changes, "recurrence", t.recurrence).strip();
    _set_status(t, status);
    return _view(t);
}

def:protect complete_task(id: str) -> TaskView {
    t = _find(id);
    _set_status(t, TaskStatus.DONE);
    return _view(t);
}

def _status(s: str) -> TaskStatus {
    try {
        return TaskStatus(s);
    } except ValueError {
        raise ValueError("status must be todo, scheduled, or done");
    }
}

def _set_status(t: Task, status: TaskStatus) -> None {
    if status == t.status {
        return;
    }
    t.status = status;
    t.completed_at = to_iso(now_utc()) if status == TaskStatus.DONE else "";
}

def:protect delete_task(id: str) -> bool {
    t = _find(id);
    del t;                             # deleting a node also removes its edges
    return True;
}
