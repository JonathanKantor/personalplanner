"""Demo data so the planner can be shown without a Google account.

Dates are relative to "now", so the demo always looks like this week.
Re-running replaces the previous demo data (anything with is_demo=True) and
leaves your own tasks alone.
"""

import from datetime { timedelta }
import from core.models { Task, Priority }
import from core.timeutil { now_utc, to_iso, zone }
import from core.preferences { _prefs }

"""One demo task: due `days` from today at `hour` o'clock local time."""
obj DemoTask {
    has title: str, days: int, hour: int, priority: Priority, minutes: int, course: str;
}

glob DEMO_TASKS: list[DemoTask] = [
    DemoTask(title="Problem set 4", days=2, hour=23, priority=Priority.HIGH, minutes=180, course="EECS 376"),
    DemoTask(title="Read chapter 7", days=1, hour=10, priority=Priority.MEDIUM, minutes=60, course="PSYCH 111"),
    DemoTask(title="Project milestone writeup", days=4, hour=17, priority=Priority.HIGH, minutes=240, course="EECS 449"),
    DemoTask(title="Lab report draft", days=3, hour=23, priority=Priority.MEDIUM, minutes=120, course="PHYSICS 240"),
    DemoTask(title="Review lecture notes", days=5, hour=12, priority=Priority.LOW, minutes=45, course="EECS 376"),
    DemoTask(title="Email advisor about schedule", days=1, hour=17, priority=Priority.LOW, minutes=15, course="")
];

def:protect seed_demo_data -> dict {
    p = _prefs();
    # Remove the previous demo tasks so seeding twice doesn't duplicate.
    old = [t for t in [root -->][?:Task] if t.is_demo];
    removed = len(old);
    for t in old {
        del t;
    }
    today = now_utc().astimezone(zone(p.timezone)).replace(
        minute=0, second=0, microsecond=0
    );
    for d in DEMO_TASKS {
        due = (today + timedelta(days=d.days)).replace(hour=d.hour);
        root ++> Task(
            title=d.title,
            due=to_iso(due),
            priority=d.priority,
            estimated_minutes=d.minutes,
            category=d.course,
            created_at=to_iso(now_utc()),
            is_demo=True
        );
    }
    return {"tasks_created": len(DEMO_TASKS), "tasks_removed": removed};
}
