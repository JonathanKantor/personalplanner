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
import from core.views { get_day_view }
import from core.tasks { create_task, _set_status }
import from core.planner { replan_if_pending, _update_task_status, _view }
import from core.planning { suggest_schedule }
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
    has days: int = 7,
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
