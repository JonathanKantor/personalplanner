"""The mobile app's API: walkers.

Why walkers here (the web app calls functions instead): the mobile app is a
separate app in the workspace, and Jac only lets one app call another's
*walkers* or `def:pub` functions. These walkers are plain `walker` (not
`:pub`), so they require login and run on the caller's own root, exactly like
the `def:protect` functions the web app uses.

Jac walker concepts used here:
- `root spawn W(...)` (on the client) starts walker W at the user's root.
- `can x with Task entry { ... }` runs when the walker arrives at a Task node;
  `here` is that node, `self` is the walker.
- `visit [...]` queues the next nodes to go to; `report v` sends v back to the
  caller (in `result.reports`); `disengage` stops the walk early.
"""

import from datetime { datetime }        # server anchor (see core/tasks.jac)
import from core.models {
    Task, TaskStatus, TimeBlock, BlockStatus, ScheduledAs, DayView, TaskView,
    BlockView, PlanView
}
import from core.models {
    WeekView, ComingUpView, PreferencesView, CanvasPreview,
    CanvasImportResult, ChatReply, ChatMessage, AssistantStatus
}
import from core.views { get_day_view, get_week_view, get_coming_up }
import from core.tasks { create_task, _set_status, list_tasks, get_task, update_task, delete_task }
import from core.planner { replan_if_pending, _update_task_status, _view }
import from core.planning { suggest_schedule, accept_all, clear_suggestions, adjust_block }
import from core.events { create_event, update_event, delete_event, EventResult }
import from core.preferences { get_preferences, update_preferences }
import from core.canvas { canvas_sync, canvas_import, canvas_feed_url }
import from core.assistant { assistant_chat, assistant_history, assistant_reset, assistant_status }
import from core.changes { as_int }
import from core.seed { seed_demo_data }

"""Today's (or `day`'s) classes, events, planned blocks and due tasks."""
walker DayScreen {
    has day: str = "",
        reports: list[DayView] = [];

    can show with Root entry {
        report get_day_view(self.day);
    }
}

"""Check off a task: walk root -> each Task until the matching one is found."""
walker FinishTask {
    has task_id: str,
        reports: list[TaskView] = [];

    can start with Root entry {
        visit [-->][?:Task];                     # go to every task of this user
    }

    can finish with Task entry {
        if jid(here) != self.task_id {
            skip;                                # not this one; keep walking
        }
        _set_status(here, TaskStatus.DONE);
        report here.to_view();
        disengage;                               # found it; stop the walk
    }

    can done with Root exit {
        replan_if_pending();                     # its pending suggestions free up
    }
}

"""Accept or reject a suggested block: walk root -> Task -> (ScheduledAs edge) -> TimeBlock."""
walker DecideBlock {
    has block_id: str,
        accept: bool,
        reports: list[BlockView] = [];

    can start with Root entry {
        visit [-->][?:Task];
    }

    can into_blocks with Task entry {
        visit [->:ScheduledAs:->][?:TimeBlock];  # follow only ScheduledAs edges
    }

    can decide with TimeBlock entry {
        if jid(here) != self.block_id {
            skip;
        }
        here.status = BlockStatus.ACCEPTED if self.accept else BlockStatus.REJECTED;
        task = [here <-:ScheduledAs:<-][?:Task][0];   # walk the edge backwards to its task
        _update_task_status(task);
        report _view(task, here);
        disengage;
    }
}

"""Quick-add a task from the phone. `due` is local "YYYY-MM-DD" or "YYYY-MM-DDTHH:MM"."""
walker QuickAdd {
    has title: str,
        due: str,
        estimated_minutes: int = 60,
        priority: str = "medium",
        reports: list[TaskView] = [];

    can add with Root entry {
        # as_int: an omitted int field can arrive as a string (core/changes.jac).
        report create_task(self.title, self.due, self.priority, as_int(self.estimated_minutes, "estimated_minutes"));
    }
}

"""Plan the next `days` days, same as the web's "Suggest schedule"."""
walker PlanAhead {
    has days: int = 21,
        reports: list[PlanView] = [];

    can plan with Root entry {
        report suggest_schedule(as_int(self.days, "days"));
    }
}

"""Load the demo classes and tasks (same as the web Settings button)."""
walker LoadDemo {
    has reports: list[dict] = [];

    can load with Root entry {
        report seed_demo_data();
    }
}

# ------------------------------------------------------------------ the redesigned app
# One walker per screen action. Each runs at the caller's root and calls the
# same core function the web app uses, so phone and web behave the same.
# Bool/int fields are always sent by the app (an omitted one can arrive as a
# string; see core/changes.jac).

"""The week containing `start` (local YYYY-MM-DD; "" = this week)."""
walker WeekScreen {
    has start: str = "",
        reports: list[WeekView] = [];

    can show with Root entry {
        report get_week_view(self.start);
    }
}

"""The "Coming up" card for the week containing `start`."""
walker ComingUpData {
    has start: str = "",
        limit: int = 5,
        reports: list[ComingUpView] = [];

    can show with Root entry {
        report get_coming_up(as_int(self.limit, "limit"), self.start);
    }
}

walker AcceptAllBlocks {
    has reports: list[list[BlockView]] = [];

    can run with Root entry {
        report accept_all();
    }
}

"""Remove every pending suggestion; reports how many were removed."""
walker ClearSuggestions {
    has reports: list[int] = [];

    can run with Root entry {
        report clear_suggestions();
    }
}

"""Change a block's time (local `day` YYYY-MM-DD, `start`/`end` HH:MM); also accepts it."""
walker MoveBlock {
    has block_id: str,
        day: str,
        start: str,
        end: str,
        reports: list[BlockView] = [];

    can run with Root entry {
        report adjust_block(self.block_id, self.day + "T" + self.start, self.day + "T" + self.end);
    }
}

"""Open tasks (or all, with `show_all`), soonest due first."""
walker TaskList {
    has show_all: bool = False,
        reports: list[list[TaskView]] = [];

    can show with Root entry {
        report list_tasks("all" if self.show_all == True else "");
    }
}

walker TaskDetail {
    has task_id: str,
        reports: list[TaskView] = [];

    can show with Root entry {
        report get_task(self.task_id);
    }
}

"""Add a task (`task_id` "") or save changes to one. `due` is local
"YYYY-MM-DDTHH:MM"; `recurrence` only applies when adding."""
walker SaveTask {
    has title: str,
        due: str,
        task_id: str = "",                   # "" = add a new task
        priority: str = "medium",
        estimated_minutes: int = 60,
        category: str = "",
        notes: str = "",
        recurrence: str = "",
        reports: list[TaskView] = [];

    can save with Root entry {
        minutes = as_int(self.estimated_minutes, "estimated_minutes");
        if self.task_id {
            report update_task(self.task_id, {
                "title": self.title, "due": self.due, "priority": self.priority,
                "estimated_minutes": minutes, "category": self.category, "notes": self.notes
            });
        } else {
            report create_task(self.title, self.due, self.priority, minutes, self.notes, self.category, self.recurrence);
        }
    }
}

"""Un-finish a task (the round checkbox, tapped again)."""
walker ReopenTask {
    has task_id: str,
        reports: list[TaskView] = [];

    can run with Root entry {
        report update_task(self.task_id, {"status": "todo"});
    }
}

walker RemoveTask {
    has task_id: str,
        reports: list[bool] = [];

    can run with Root entry {
        report delete_task(self.task_id);
    }
}

"""Add one of your own events (`event_id` "") or change one occurrence.
`day` YYYY-MM-DD, `start`/`end` HH:MM; `weeks` > 1 repeats it weekly (new only)."""
walker SaveEvent {
    has title: str,
        day: str,
        start: str,
        end: str,
        event_id: str = "",                  # "" = add a new event
        weeks: int = 1,
        is_class: bool = False,
        reports: list[EventResult] = [];

    can save with Root entry {
        if self.event_id {
            report update_event(self.event_id, {"title": self.title, "day": self.day, "start": self.start, "end": self.end});
        } else {
            report create_event(self.title, self.day, self.start, self.end, self.is_class == True, as_int(self.weeks, "weeks"));
        }
    }
}

"""Delete one of your events; `whole_series` deletes every repeat."""
walker RemoveEvent {
    has event_id: str,
        whole_series: bool = False,
        reports: list[int] = [];

    can run with Root entry {
        report delete_event(self.event_id, self.whole_series == True);
    }
}

walker Prefs {
    has reports: list[PreferencesView] = [];

    can show with Root entry {
        report get_preferences();
    }
}

"""Change some preferences, e.g. changes={"work_end": "20:00"}."""
walker SavePrefs {
    has changes: dict = {},
        reports: list[PreferencesView] = [];

    can save with Root entry {
        report update_preferences(self.changes);
    }
}

"""The saved Canvas feed link ("" if none yet)."""
walker CanvasFeed {
    has reports: list[str] = [];

    can show with Root entry {
        report canvas_feed_url();
    }
}

"""Read the Canvas feed (saved link if `url` is "") and list its assignments."""
walker CanvasLoad {
    has url: str = "",
        reports: list[CanvasPreview] = [];

    can run with Root entry {
        report canvas_sync(self.url);
    }
}

"""Import the ticked assignments (same `choices` as the web page sends)."""
walker CanvasImport {
    has choices: list[dict] = [],
        reports: list[CanvasImportResult] = [];

    can run with Root entry {
        report canvas_import(self.choices);
    }
}

"""Assistant status and the conversation so far."""
walker ChatState {
    has reports: list[any] = [];

    can show with Root entry {
        report assistant_status();
        report assistant_history();
    }
}

walker ChatSend {
    has message: str,
        reports: list[ChatReply] = [];

    can run with Root entry {
        report assistant_chat(self.message);
    }
}

walker ChatReset {
    has reports: list[bool] = [];

    can run with Root entry {
        report assistant_reset();
    }
}

