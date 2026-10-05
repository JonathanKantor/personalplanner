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
        max_focus_minutes_per_day: int = 360,
        display_name: str = "",                   # shown in the web header ("" = username)
        city: str = "";                           # shown next to today's date
}

obj PreferencesView {
    has timezone: str,
        work_start: str,
        work_end: str,
        days_off: list[str],
        preferred_start: str,
        preferred_end: str,
        min_break_minutes: int,
        max_focus_minutes_per_day: int,
        display_name: str = "",
        city: str = "";
}

# ---------------------------------------------------------------- Tasks

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
        completed_at: str,
        parent_id: str;
}

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
        parent_id: str = "",                      # set on later occurrences of a recurring task
        source_uid: str = "",                     # Canvas assignment UID if imported from Canvas
        source_url: str = "",                     # link to the assignment in Canvas
        is_demo: bool = False;                    # created by seed_demo_data

    """The API shape of this task. jid(self) is the node's stable id; it
    survives restarts and the trip over the network."""
    def to_view -> TaskView {
        return TaskView(
            id=jid(self), title=self.title, notes=self.notes, due=self.due,
            priority=str(self.priority), status=str(self.status),
            estimated_minutes=self.estimated_minutes, category=self.category,
            recurrence=self.recurrence, created_at=self.created_at,
            completed_at=self.completed_at, parent_id=self.parent_id
        );
    }
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

"""Calendar --InCalendar--> CalendarEvent"""
edge InCalendar {}

"""The user's Google connection. One per user, attached to root. The refresh
token lives here (per user, in the database) - never in code or in git."""
node GoogleAccount {
    has refresh_token: str = "",
        oauth_state: str = "",                    # anti-forgery value for the OAuth redirect
        connected_at: str = "";
}

"""One event occurrence as delivered by a source (.ics file or Google), before
it is stored. Both sources produce this same shape, so the code that saves
events (core/calendars.jac) doesn't care where they came from."""
obj Occurrence {
    has external_id: str,
        series_id: str,
        title: str,
        start: str,                               # UTC ISO datetime
        end: str,
        all_day: bool;
}

obj SyncResult {
    has calendar: str,
        added: int = 0,
        updated: int = 0,
        removed: int = 0,
        total: int = 0;
}

obj CalendarView {
    has id: str,
        source: str,
        name: str,
        is_class: bool,
        last_synced: str,
        event_count: int;
}

obj EventView {
    has id: str,
        calendar_id: str,
        series_id: str,
        title: str,
        start: str,
        end: str,
        all_day: bool,
        is_class: bool,
        editable: bool = False;                   # True for your own events ("My events")
}

"""A recurring series, so the user can mark e.g. "EECS 376 Lecture" as a class."""
obj SeriesView {
    has series_id: str,
        title: str,
        calendar: str,
        occurrences: int,
        is_class: bool;
}

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

obj BlockView {
    has id: str,
        task_id: str,
        task_title: str,
        category: str,
        priority: str,
        start: str,
        end: str,
        status: str,
        reason: str,
        session: int,
        sessions_total: int;
}

"""A task (or the part of one) the scheduler could not fit, and why."""
obj UnscheduledView {
    has task_id: str,
        title: str,
        minutes_needed: int,
        minutes_placed: int,
        reason: str;
}

obj PlanView {
    has window_start: str,
        window_end: str,
        suggestions: list[BlockView],
        unscheduled: list[UnscheduledView];
}

"""Everything for a date range: calendar events, planned blocks, tasks due."""
obj AgendaView {
    has start: str,
        end: str,
        timezone: str,
        events: list[EventView],
        blocks: list[BlockView],
        due: list[TaskView];
}

obj ProgressView {
    has week_start: str,
        tasks_done: int,
        tasks_open: int,
        tasks_overdue: int,
        minutes_planned: int,                     # accepted blocks this week
        minutes_completed: int;                   # accepted blocks of finished tasks
}

# ---------------------------------------------------------------- client views
# Pre-computed in the user's timezone by core/views.jac so clients only draw.

"""One thing on a day: a class, another event, or a planned block."""
obj DayItem {
    has id: str,
        kind: str,                 # "class" | "event" | "block"
        title: str,
        all_day: bool,
        start_label: str,          # "2:30pm"
        end_label: str,
        start_min: int,            # minutes from local midnight
        end_min: int,
        status: str = "",          # blocks: "suggested" | "accepted"
        reason: str = "",
        task_id: str = "",
        editable: bool = False;    # events: one of your own (can be edited / dragged)
}

obj DayView {
    has date: str,                 # local YYYY-MM-DD
        label: str,                # "Mon Oct 5"
        is_today: bool,
        is_day_off: bool,
        items: list[DayItem],
        due: list[TaskView];
}

obj WeekView {
    has start: str,
        prev_start: str,
        next_start: str,
        label: str,
        timezone: str,
        work_start_min: int,
        work_end_min: int,
        days: list[DayView],
        suggested_count: int;
}

# ---------------------------------------------------------------- Canvas import
# Filled by core/canvas.jac.

"""The user's Canvas calendar feed (one per user)."""
node CanvasFeed {
    has url: str,
        last_synced: str = "",
        dismissed: list[str] = [];               # assignment UIDs the user chose not to import
}

"""One assignment found in the Canvas feed, shown in the review table."""
obj CanvasItem {
    has uid: str,
        title: str,
        course: str,
        due: str,                                 # UTC ISO datetime
        url: str,
        status: str;                              # "new" | "imported" | "dismissed" | "past_due"
}

obj CanvasPreview {
    has feed_url: str,
        items: list[CanvasItem],
        courses: list[str],
        updated: int = 0;                         # imported tasks whose due date/title were refreshed
}

obj CanvasImportResult {
    has created: int = 0,
        dismissed: int = 0,
        skipped: int = 0;
}

# ---------------------------------------------------------------- AI assistant
# Filled by core/assistant.jac.

"""The user's conversation with the assistant (one per user).
`messages` is the model-facing history (byLLM's format, includes tool calls);
`transcript` is what the chat window shows."""
node ChatThread {
    has messages: list[dict] = [],
        transcript: list[dict] = [],
        updated_at: str = "";
}

obj ChatMessage {
    has role: str,                                # "user" | "assistant"
        text: str,
        actions: list[str] = [];                  # what the assistant changed
}

obj ChatReply {
    has reply: str,
        actions: list[str] = [],
        error: str = "";
}

obj AssistantStatus {
    has configured: bool,
        model: str;
}
