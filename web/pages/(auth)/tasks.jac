"""/tasks - every task, soonest due first.

Round checkbox: finish a task (or reopen a finished one). Click a task to
edit or delete it, "Add task" to create one; both use the TaskEditor dialog.
"""

import from core.tasks { list_tasks, update_task, complete_task }
import from core.preferences { get_preferences }
import type from core.models { TaskView }
import from ...components.TaskEditor { TaskEditor }
import from ...components.PageHeader { PageHeader }
import from ...components.kit { Button, Card, Chip, CheckCircle, Segmented, Choice }
import from ...lib.ui { error_text }

def:pub TasksPage() -> JsxPage {
    has tasks: list[TaskView] = [],
        loaded: bool = False,
        show: str = "open",                  # "open" | "all"
        error: str = "",
        tz: str = "",
        open_task: str = "",                 # task open in the editor ("" = closed)
        adding: bool = False;                # "Add task" dialog open

    async def load {
        try {
            got = await list_tasks("all" if show == "all" else "");
            tasks = sorted(got, key=lambda (t: TaskView) { t.due; });
            loaded = True;
        } except Exception as e {
            error = error_text(e);
        }
    }

    async can with [show] entry {
        if not tz {
            tz = (await get_preferences()).timezone;
        }
        await load();
    }

    """"Due Wed, Oct 7, 5:00 PM" in the user's timezone."""
    def due_label(iso: str) -> str {
        return new(Date, iso).toLocaleString("en-US", {  # jac:ignore[E1053]
            "timeZone": tz, "weekday": "short", "month": "short", "day": "numeric",
            "hour": "numeric", "minute": "2-digit"
        });
    }

    async def toggle(t: TaskView) {
        error = "";
        try {
            if t.status == "done" {
                await update_task(t.id, {"status": "todo"});
            } else {
                await complete_task(t.id);
            }
        } except Exception as ex {
            error = error_text(ex);
        }
        await load();
    }

    open_count = len([t for t in tasks if t.status != "done"]);

    <div>
        <PageHeader eyebrow="Everything on your list" title="Tasks"
                    subtitle="Soonest due first. Click a task to edit it; the planner fits open ones around your classes.">
            <Button id="add-task" label="Add task" icon="plus" variant="primary" onClick={lambda (e: MouseEvent) { adding = True; }} />
        </PageHeader>
        {error and <div className="error">{error}</div>}

        <Card className="task-card">
            <div className="task-toolbar">
                <span className="side-card-head">{str(open_count) + " open"}</span>
                <span className="spacer"></span>
                <Segmented label="Which tasks" value={show} onChange={lambda (v: str) { show = v; }}
                    options={[Choice(value="open", label="Open"), Choice(value="all", label="All")]} />
            </div>

            {if not loaded {
                <div className="task-body" aria-label="Loading">
                    {for i in [1, 2, 3, 4] { <div key={str(i)} className="skeleton-row"></div> }}
                </div>
            } elif len(tasks) == 0 {
                <div className="empty-state">
                    <p className="empty-title">{"Nothing on your list." if show == "open" else "No tasks yet."}</p>
                    <p className="hint">Add one here, import assignments from Canvas, or ask Morrow.</p>
                </div>
            } else {
                <ul className="item-list task-body">
                    {for t in tasks {
                        <li key={t.id} className={"item-row" + (" done" if t.status == "done" else "")}>
                            <CheckCircle checked={t.status == "done"}
                                label={("Reopen: " if t.status == "done" else "Mark done: ") + t.title}
                                onToggle={lambda { toggle(t); }} />
                            <button type="button" className="item-main" onClick={lambda (e: MouseEvent) { open_task = t.id; }}>
                                <span className="item-title">{t.title}</span>
                                <span className="item-sub num">
                                    Due {due_label(t.due)} · {str(t.estimated_minutes)} min{(" · " + t.notes) if t.notes else ""}
                                </span>
                            </button>
                            <span className="item-chips">
                                {t.category and <Chip label={t.category} />}
                                {(t.priority == "high" and t.status != "done") and <Chip label="High" tone="danger" />}
                                {t.status == "scheduled" and <Chip label="Planned" tone="accent" />}
                                {t.recurrence and <Chip label="Repeats" />}
                            </span>
                        </li>
                    }}
                </ul>
            }}
        </Card>

        {open_task and <TaskEditor taskId={open_task} tz={tz}
                onClose={lambda { open_task = ""; }} onChanged={lambda { load(); }} />}
        {adding and <TaskEditor taskId="" tz={tz}
                onClose={lambda { adding = False; }} onChanged={lambda { load(); }} />}
    </div>
}
