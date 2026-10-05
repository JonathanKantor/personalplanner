"""AI planning assistant: chat to plan your schedule.

The assistant is a byLLM function (`by llm(...)`) that can only act through
the planner tools below. It never invents times: to plan, it runs the same
deterministic scheduler as everything else (core/scheduler.jac) and explains
the result. There is deliberately no delete tool.

Jac/byLLM concepts used here:
- `def f(...) -> str by llm(tools=[...])`: the body is replaced by a model
  call. Given `tools`, the model may call those functions (a ReAct loop)
  before answering.
- `sem x = "..."`: the description of x that the model sees. Tools and their
  parameters are explained to the model this way, not with docstrings.
- `conversation=`: a list of earlier messages; byLLM reads it and appends the
  new turn to it, which gives the assistant memory between messages.

Model: a fallback pool of Gemini free-tier models (DEFAULT_MODELS below): if
one is overloaded or unavailable, the next is tried. Override with
BYLLM_DEFAULT_MODEL in .env (one name, or several separated by commas).
Key: GEMINI_API_KEY (or GOOGLE_API_KEY) in .env.
"""

import os;
import json;
import contextvars;
import logging;
import from datetime { datetime, timedelta }
import from jaclang.byllm.lib { Model, ModelPool }
import from core.models { ChatThread, ChatMessage, ChatReply, AssistantStatus }
import from core.timeutil { now_utc, to_iso, zone, local_label }
import from core.preferences { _prefs, get_preferences, update_preferences }
import from core.tasks { create_task, list_tasks, update_task, complete_task }
import from core.planning { suggest_schedule, accept_block, reject_block, accept_all, adjust_block, clear_suggestions }
import from core.events { create_event }
import from core.views { get_day_view }

# Checked against the Gemini API on 2026-10-05 (gemini-2.5-flash is retired
# for new keys; the newest models often return 503 "high demand").
glob DEFAULT_MODELS: list[str] = [
    "gemini/gemini-3.6-flash", "gemini/gemini-3.5-flash-lite", "gemini/gemini-3.1-flash-lite"
],
     MAX_HISTORY: int = 60,                  # model-facing messages kept per user
     MAX_TRANSCRIPT: int = 200;              # chat-window messages kept per user

def _model_names -> list[str] {
    configured = os.environ.get("BYLLM_DEFAULT_MODEL", "");
    names = [n.strip() for n in configured.split(",") if n.strip()];
    return names or DEFAULT_MODELS;
}

# The model behind `by llm(...)` below: a ModelPool tries each model in order
# and moves on when one fails (e.g. "high demand"). Tests replace it with a MockLLM.
glob llm: any = ModelPool(models=[Model(model_name=n) for n in _model_names()], strategy="fallback", num_retries=1);

# Per-request state. A ContextVar is like a global, but each request (thread)
# sees its own value, so two users chatting at once don't mix histories.
glob _history_var: any = contextvars.ContextVar("assistant_history"),
     _actions_var: any = contextvars.ContextVar("assistant_actions");

def _log(action: str) -> None {
    _actions_var.get().append(action);
}

def _tz -> str {
    return _prefs().timezone;
}

def _when(iso: str) -> str {
    return local_label(iso, _tz());
}

# ------------------------------------------------------------------ tools
# Each tool returns short text for the model. Errors come back as text
# ("Error: ...") so the model can correct itself instead of failing the chat.

def tool_today -> str {
    now = now_utc().astimezone(zone(_tz()));
    return now.strftime("%A %Y-%m-%d %H:%M") + " (" + _tz() + ")";
}
sem tool_today = "Current local date, weekday and time. Use it to resolve words like 'tomorrow' or 'Thursday'.";

def tool_schedule(start_date: str, days: int) -> str {
    try {
        d = datetime.fromisoformat(start_date).date() if start_date else now_utc().astimezone(zone(_tz())).date();
    } except ValueError {
        return "Error: start_date must be YYYY-MM-DD";
    }
    days = max(1, min(int(days), 14));
    lines: list[str] = [];
    for i in range(days) {
        view = get_day_view((d + timedelta(days=i)).isoformat());
        lines.append(view.label + (" (day off)" if view.is_day_off else "") + ":");
        for it in view.items {
            what = "class" if it.kind == "class" else ("event" if it.kind == "event" else f"{it.status} block [block_id={it.id}] for task [task_id={it.task_id}]");
            lines.append(f"  {it.start_label}-{it.end_label} {what}: {it.title}");
        }
        for t in view.due {
            lines.append(f"  DUE {_when(t.due)}: {t.title} [task_id={t.id}] ({t.status})");
        }
        if not view.items and not view.due {
            lines.append("  (nothing)");
        }
    }
    return "\n".join(lines);
}
sem tool_schedule = "Show the calendar for a range of days: classes, events, planned (accepted) and suggested blocks with their ids, and tasks due.";
sem tool_schedule.start_date = "First day, YYYY-MM-DD; empty string for today.";
sem tool_schedule.days = "Number of days to show (1-14).";

def tool_tasks(include_done: bool) -> str {
    tasks = list_tasks("all" if include_done else "");
    if not tasks {
        return "No tasks.";
    }
    return "\n".join([
        f"[task_id={t.id}] {t.title}" + (f" ({t.category})" if t.category else "")
        + f" - due {_when(t.due)}, {t.estimated_minutes} min, {t.priority} priority, {t.status}"
        for t in tasks
    ]);
}
sem tool_tasks = "List the user's tasks with ids, due dates, estimates, priorities and status.";
sem tool_tasks.include_done = "True to include finished tasks.";

def tool_add_task(title: str, due: str, estimated_minutes: int, priority: str, course: str) -> str {
    try {
        t = create_task(title, due, priority or "medium", int(estimated_minutes), "", course);
    } except ValueError as e {
        return "Error: " + str(e);
    }
    _log(f"Added task \"{t.title}\" (due {_when(t.due)}, {t.estimated_minutes} min)");
    return f"Added [task_id={t.id}] {t.title}, due {_when(t.due)}.";
}
sem tool_add_task = "Create a task. Only use when the user asks to add something.";
sem tool_add_task.title = "Short task title.";
sem tool_add_task.due = "Due date in the user's local time: YYYY-MM-DD (end of day) or YYYY-MM-DDTHH:MM.";
sem tool_add_task.estimated_minutes = "How long the work takes, in minutes (ask the user if unknown).";
sem tool_add_task.priority = "high, medium or low.";
sem tool_add_task.course = "Course or category, or empty string.";

def tool_update_task(task_id: str, due: str, estimated_minutes: int, priority: str, title: str) -> str {
    changes: dict = {};
    if due { changes["due"] = due; }
    if estimated_minutes > 0 { changes["estimated_minutes"] = int(estimated_minutes); }
    if priority { changes["priority"] = priority; }
    if title { changes["title"] = title; }
    if not changes {
        return "Error: nothing to change.";
    }
    try {
        t = update_task(task_id, changes);
    } except ValueError as e {
        return "Error: " + str(e);
    }
    _log(f"Updated \"{t.title}\" ({', '.join(changes.keys())})");
    return f"Updated {t.title}: due {_when(t.due)}, {t.estimated_minutes} min, {t.priority}.";
}
sem tool_update_task = "Change a task. Pass empty string / 0 for fields that should stay the same.";
sem tool_update_task.task_id = "The task's id from tool_tasks or tool_schedule.";
sem tool_update_task.due = "New due date (YYYY-MM-DD or YYYY-MM-DDTHH:MM, local) or empty string.";
sem tool_update_task.estimated_minutes = "New estimate in minutes, or 0.";
sem tool_update_task.priority = "high, medium, low, or empty string.";
sem tool_update_task.title = "New title or empty string.";

def tool_complete_task(task_id: str) -> str {
    try {
        t = complete_task(task_id);
    } except ValueError as e {
        return "Error: " + str(e);
    }
    _log(f"Marked \"{t.title}\" done");
    return f"Marked {t.title} done.";
}
sem tool_complete_task = "Mark a task as done.";
sem tool_complete_task.task_id = "The task's id.";

def tool_plan(days: int) -> str {
    plan = suggest_schedule(max(1, min(int(days), 28)));
    _log(f"Planned the next {days} day(s): {len(plan.suggestions)} suggestion(s)");
    lines = [f"[block_id={b.id}] {_when(b.start)}-{local_label(b.end, _tz())[-5:]} {b.task_title} - {b.reason}" for b in plan.suggestions];
    lines += [f"COULD NOT FIT {u.title}: {u.reason}" for u in plan.unscheduled];
    return "\n".join(lines) if lines else "Nothing to plan: no open tasks need time.";
}
sem tool_plan = "Run the deterministic scheduler: replaces earlier SUGGESTED blocks with new suggestions (accepted blocks never move) and returns them with block ids and reasons. Suggestions are not final until accepted.";
sem tool_plan.days = "How many days ahead to plan (1-28, usually 7).";

def tool_accept(block_ids: list[str]) -> str {
    try {
        if block_ids == ["all"] {
            done = accept_all();
            _log(f"Accepted all {len(done)} suggestion(s)");
            return f"Accepted {len(done)} block(s).";
        }
        names = [accept_block(b).task_title for b in block_ids];
    } except ValueError as e {
        return "Error: " + str(e);
    }
    _log("Accepted " + ", ".join(names));
    return "Accepted: " + ", ".join(names);
}
sem tool_accept = "Accept suggested blocks so they become fixed in the calendar. Only when the user agrees.";
sem tool_accept.block_ids = "Block ids to accept, or [\"all\"] for every current suggestion.";

def tool_reject(block_id: str) -> str {
    try {
        b = reject_block(block_id);
    } except ValueError as e {
        return "Error: " + str(e);
    }
    _log(f"Rejected a slot for \"{b.task_title}\"");
    return f"Rejected that slot for {b.task_title}. Run tool_plan again for an alternative.";
}
sem tool_reject = "Reject one suggested block (that slot won't be offered again for its task).";
sem tool_reject.block_id = "The suggested block's id.";

def tool_move_block(block_id: str, start: str, end: str) -> str {
    try {
        b = adjust_block(block_id, start, end);
    } except ValueError as e {
        return "Error: " + str(e);
    }
    _log(f"Moved \"{b.task_title}\" to {_when(b.start)}");
    return f"Moved {b.task_title} to {_when(b.start)} and accepted it.";
}
sem tool_move_block = "Move or resize a block to a specific time (this also accepts it). Fails if it overlaps a class/event or another accepted block.";
sem tool_move_block.block_id = "The block's id.";
sem tool_move_block.start = "New start, local YYYY-MM-DDTHH:MM.";
sem tool_move_block.end = "New end, local YYYY-MM-DDTHH:MM.";

def tool_add_event(title: str, date: str, start: str, end: str, repeat_weeks: int) -> str {
    try {
        r = create_event(title, date, start, end, False, max(1, int(repeat_weeks)));
    } except ValueError as e {
        return "Error: " + str(e);
    }
    first = r.events[0];
    _log(f"Added event \"{first.title}\" ({_when(first.start)}" + (f", weekly x{len(r.events)}" if len(r.events) > 1 else "") + ")");
    note = (" WARNING: it overlaps planned blocks: " + ", ".join(r.conflicts)) if r.conflicts else "";
    return f"Added {len(r.events)} event(s) starting {_when(first.start)}.{note}";
}
sem tool_add_event = "Add a fixed commitment the user tells you about (meeting, appointment, shift) to their calendar. The scheduler will plan around it.";
sem tool_add_event.title = "Short title, e.g. 'Advisor meeting'.";
sem tool_add_event.date = "Local date YYYY-MM-DD.";
sem tool_add_event.start = "Start time HH:MM (24-hour).";
sem tool_add_event.end = "End time HH:MM (24-hour).";
sem tool_add_event.repeat_weeks = "1 for a one-off; N to repeat weekly N times.";

def tool_clear_suggestions -> str {
    n = clear_suggestions();
    _log(f"Cleared {n} suggestion(s)");
    return f"Cleared {n} suggested block(s); planned blocks are unchanged.";
}
sem tool_clear_suggestions = "Remove all pending suggested blocks (accepted/planned blocks stay).";

def tool_preferences -> str {
    p = get_preferences();
    return json.dumps({
        "timezone": p.timezone, "work_start": p.work_start, "work_end": p.work_end,
        "days_off": p.days_off, "preferred_start": p.preferred_start,
        "preferred_end": p.preferred_end, "min_break_minutes": p.min_break_minutes,
        "max_focus_minutes_per_day": p.max_focus_minutes_per_day
    });
}
sem tool_preferences = "Show the scheduling preferences (working hours, days off, preferred study window, breaks, daily focus cap).";

def tool_set_preferences(changes_json: str) -> str {
    try {
        changes = json.loads(changes_json);
        update_preferences(changes);
    } except (ValueError, TypeError) as e {
        return "Error: " + str(e);
    }
    _log("Changed preferences: " + ", ".join([f"{k}={v}" for (k, v) in changes.items()]));
    return "Preferences updated.";
}
sem tool_set_preferences = "Change scheduling preferences. Only when the user asks.";
sem tool_set_preferences.changes_json = "JSON object of fields to change, e.g. {\"work_end\": \"20:00\", \"days_off\": [\"sat\"], \"max_focus_minutes_per_day\": 240}. Times are HH:MM.";

glob TOOLS: list = [
    tool_today, tool_schedule, tool_tasks, tool_add_task, tool_update_task,
    tool_complete_task, tool_plan, tool_accept, tool_reject, tool_move_block,
    tool_add_event, tool_clear_suggestions, tool_preferences, tool_set_preferences
];

glob SYSTEM: str = (
    "You are the user's planning assistant inside a student schedule planner. "
    + "Use the tools to look at their real calendar and tasks before answering; never guess times or ids. "
    + "To find time for work, call tool_plan (the planner's own scheduler) and present its suggestions with the reasons; "
    + "do not invent your own time slots. Suggestions are not final: accept them (tool_accept) only when the user agrees, "
    + "unless they clearly asked you to schedule it for them. Ask for an estimate if a new task has none. "
    + "Use the user's local time, 12-hour clock, and be brief: short sentences or a few bullet points. "
    + "Write plain text only, no Markdown (no ** or #); start list items with '- '."
);

# ------------------------------------------------------------------ the model call

def _history -> list {
    return _history_var.get();
}

def _assistant_turn(message: str) -> str by llm(
    tools=TOOLS,
    conversation=_history(),
    system_prompt=SYSTEM,
    max_react_iterations=12,
    incl_info={"now": tool_today()}
);
sem _assistant_turn = "Reply to the user's latest message as their planning assistant, using the tools as needed.";
sem _assistant_turn.message = "The user's latest chat message.";

# ------------------------------------------------------------------ helpers

def _thread -> ChatThread {
    found = [root -->][?:ChatThread];
    return found[0] if found else (root ++> ChatThread());
}

"""Keep the last messages, cutting only where a user message starts so a tool
call is never separated from its result."""
def _trim(messages: list[dict]) -> list[dict] {
    if len(messages) <= MAX_HISTORY {
        return messages;
    }
    starts = [i for (i, m) in enumerate(messages) if m.get("role") == "user" and i >= len(messages) - MAX_HISTORY];
    return messages[starts[0]:] if starts else messages[-MAX_HISTORY:];
}

def _api_key_set -> bool {
    return bool(os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY"));
}

def _friendly(e: Exception) -> str {
    text = str(e);
    name = type(e).__name__;
    # The full error goes to the server log; the user gets a short message.
    logging.getLogger("planner.assistant").error("assistant failed: %s: %s", name, text[:2000]);
    if "Authentication" in name or "API key" in text or "api_key" in text.lower() {
        return "The AI key isn't valid or isn't set. Add GEMINI_API_KEY to .env and restart the server (see README).";
    }
    if "RateLimit" in name or "429" in text or "quota" in text.lower() {
        return "The free AI quota is used up for now. Wait a minute (or until tomorrow) and try again.";
    }
    if "503" in text or "high demand" in text or "overloaded" in text.lower() or "Unavailable" in name {
        return "The AI models are busy right now. Try again in a minute.";
    }
    if "no longer available" in text or ("NotFound" in name and "model" in text.lower()) {
        return "The AI model isn't available to your key. Set BYLLM_DEFAULT_MODEL in .env (see README).";
    }
    return "The assistant ran into a problem: " + text[:200];
}

# ------------------------------------------------------------------ endpoints

def:protect assistant_status -> AssistantStatus {
    names = _model_names();
    return AssistantStatus(
        configured=_api_key_set() or not names[0].startswith("gemini/"),
        model=names[0].split("/")[-1] + (f" (+{len(names) - 1} fallback)" if len(names) > 1 else "")
    );
}

"""Send a chat message; returns the reply and a list of changes made."""
def:protect assistant_chat(message: str) -> ChatReply {
    message = message.strip();
    if not message {
        raise ValueError("Type a message first.");
    }
    if len(message) > 2000 {
        raise ValueError("That message is too long (2000 characters max).");
    }
    # litellm reads GEMINI_API_KEY; accept GOOGLE_API_KEY too.
    if not os.environ.get("GEMINI_API_KEY") and os.environ.get("GOOGLE_API_KEY") {
        os.environ["GEMINI_API_KEY"] = os.environ["GOOGLE_API_KEY"];
    }
    thread = _thread();
    history: list = list(thread.messages);    # byLLM appends this turn to it
    actions: list[str] = [];
    _history_var.set(history);
    _actions_var.set(actions);
    try {
        reply = _assistant_turn(message);
    } except Exception as e {
        # Keep anything the tools already changed visible to the user.
        return ChatReply(reply="", actions=actions, error=_friendly(e));
    }
    reply = str(reply).strip() or "Done.";
    stamp = to_iso(now_utc());
    # Rebind (not mutate) list fields so the node change is saved.
    thread.messages = _trim(history);
    thread.transcript = (thread.transcript + [
        {"role": "user", "text": message, "actions": [], "at": stamp},
        {"role": "assistant", "text": reply, "actions": actions, "at": stamp}
    ])[-MAX_TRANSCRIPT:];
    thread.updated_at = stamp;
    return ChatReply(reply=reply, actions=actions);
}

def:protect assistant_history -> list[ChatMessage] {
    return [
        ChatMessage(role=m["role"], text=m["text"], actions=m.get("actions", []))
        for m in _thread().transcript
    ];
}

"""Start a new conversation (forgets the chat, not your tasks)."""
def:protect assistant_reset -> bool {
    t = _thread();
    t.messages = [];
    t.transcript = [];
    return True;
}
