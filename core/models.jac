"""Data model for the planner.

Jac concepts used here:
- `node` = a record stored on the graph. A node is saved (persisted) once it is
  connected, directly or indirectly, to the user's `root` node.
- `edge` = a typed connection between two nodes.
- `obj`  = a plain object that is NOT stored; used for API response shapes.
- `has`  = a field declaration.

There is no User node: Jac gives every logged-in user their own `root`, and
everything below hangs off it, so per-user isolation comes for free.

All timestamps are stored as ISO-8601 strings in UTC (e.g.
"2026-10-07T18:00:00+00:00"). Conversion to/from the user's timezone happens in
core/timeutil.jac.
"""

# `enum X: str` makes each member a real string, so it serializes as "high"
# rather than an opaque enum object.
enum Priority: str {
    LOW = "low",
    MEDIUM = "medium",
    HIGH = "high"
}

enum TaskStatus: str {
    TODO = "todo",
    SCHEDULED = "scheduled",
    DONE = "done"
}

enum BlockStatus: str {
    SUGGESTED = "suggested",
    ACCEPTED = "accepted",
    REJECTED = "rejected"
}

# ---------------------------------------------------------------- Preferences

"""One per user. Times of day are local "HH:MM" strings in `timezone`."""
node Preferences {
    has timezone: str = "America/Detroit",
        work_start: str = "09:00",
        work_end: str = "21:00",
        days_off: list[str] = [],                 # e.g. ["sat", "sun"]
        preferred_start: str = "",                # preferred study window,
        preferred_end: str = "",                  # "" = no preference
        min_break_minutes: int = 15,
        max_focus_minutes_per_day: int = 360;
}

obj PreferencesView {
    has timezone: str,
        work_start: str,
        work_end: str,
        days_off: list[str],
        preferred_start: str,
        preferred_end: str,
        min_break_minutes: int,
        max_focus_minutes_per_day: int;
}

# ---------------------------------------------------------------- Tasks

node Task {
    has title: str,
        notes: str = "",
        due: str = "",                            # UTC ISO datetime
        priority: Priority = Priority.MEDIUM,
        status: TaskStatus = TaskStatus.TODO,
        estimated_minutes: int = 60,
        category: str = "",                       # course or category, optional
        recurrence: str = "",                     # e.g. "WEEKLY:MO,WE"; "" = none
        created_at: str = "",
        completed_at: str = "",
        is_demo: bool = False;                    # created by seed_demo_data
}

"""What the API returns for a task. `id` is the node's stable graph id (jid)."""
obj TaskView {
    has id: str,
        title: str,
        notes: str,
        due: str,
        priority: str,
        status: str,
        estimated_minutes: int,
        category: str,
        recurrence: str,
        created_at: str,
        completed_at: str;
}

# ---------------------------------------------------------------- Calendar
# Filled by calendar sync (slice 2). Read-only from the planner's side.

"""A source calendar: one Google calendar, or one imported .ics feed."""
node Calendar {
    has source: str,                              # "google" or "ics"
        external_id: str,                         # Google calendar id, or ics URL/name
        name: str = "",
        is_class: bool = False,                   # every event in it counts as a class
        last_synced: str = "";
}

"""One occurrence of an event. Recurring events are stored one row per
occurrence, linked by `series_id`, so the scheduler never has to expand rules."""
node CalendarEvent {
    has external_id: str,                         # unique per occurrence within a calendar
        series_id: str = "",                      # shared by occurrences of a recurring event
        title: str = "",
        start: str = "",                          # UTC ISO datetime
        end: str = "",
        all_day: bool = False,
        is_class: bool = False,
        last_synced: str = "";
}

"""Marks a whole recurring series as a class, independent of its calendar."""
node ClassSeries {
    has series_id: str;
}

edge InCalendar {}

# ---------------------------------------------------------------- Scheduling
# Filled by the scheduler (slice 3).

node TimeBlock {
    has start: str,
        end: str,
        status: BlockStatus = BlockStatus.SUGGESTED,
        reason: str = "",
        session: int = 1,                         # 2 of 3, for split tasks
        sessions_total: int = 1;
}

"""Task --ScheduledAs--> TimeBlock (a task can have several blocks)."""
edge ScheduledAs {}
