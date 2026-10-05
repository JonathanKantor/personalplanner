"""/tasks - add tasks, and click one to edit it (TaskEditor dialog)."""

import from core.tasks { create_task, list_tasks, update_task, complete_task, delete_task }
import from core.preferences { get_preferences }
import type from core.models { TaskView }
import from ...components.TaskEditor { TaskEditor }
import from ...lib.ui { error_text }

def:pub TasksPage() -> JsxPage {
    has tasks: list[TaskView] = [],
        show_done: bool = False,
        error: str = "",
        notice: str = "",
        tz: str = "",
        open_task: str = "",                 # task open in the editor dialog
        # add-task form fields
        title: str = "",
        due: str = "",                       # "2026-10-09T17:00" from <input type=datetime-local>
        priority: str = "medium",
        minutes: str = "60",
        course: str = "",
        repeat: str = "",
        notes: str = "";

    async def load {
        try {
            tasks = await list_tasks("all" if show_done else "");
        } except Exception as e {
            error = error_text(e);
        }
    }

    async can with [show_done] entry {
        if not tz {
            tz = (await get_preferences()).timezone;
        }
        await load();
    }

    def reset_form {
        title = "";
        due = "";
        priority = "medium";
        minutes = "60";
        course = "";
        repeat = "";
        notes = "";
    }

    def local_label(iso: str) -> str {
        return new(Date, iso).toLocaleString("en-US", {
            "timeZone": tz, "weekday": "short", "month": "short", "day": "numeric",
            "hour": "numeric", "minute": "2-digit"
        });
    }

    async def save(e: FormEvent) {
        e.preventDefault();
        error = "";
        notice = "";
        try {
            await create_task(title, due, priority, int(minutes), notes, course, repeat);
            notice = "Task added. Open Week and press Suggest schedule to plan it.";
            reset_form();
        } except Exception as ex {
            error = error_text(ex);
        }
        await load();
    }

    async def mark_done(id: str) {
        try {
            await complete_task(id);
        } except Exception as ex {
            error = error_text(ex);
        }
        await load();
    }

    async def remove(id: str) {
        try {
            await delete_task(id);
        } except Exception as ex {
            error = error_text(ex);
        }
        await load();
    }

    <div>
        {open_task and <TaskEditor taskId={open_task} tz={tz}
                onClose={lambda { open_task = ""; }} onChanged={lambda { load(); }} />}
        <h1 style={{"fontSize": "20px"}}>Tasks</h1>
        {error and <div className="error">{error}</div>}
        {notice and <div className="notice">{notice}</div>}

        <form className="panel" onSubmit={save}>
            <h2>Add a task</h2>
            <div className="form-grid">
                <label className="field wide">Title
                    <input id="title" value={title} required={True}
                        onChange={lambda (e: ChangeEvent) { title = e.target.value; }} />
                </label>
                <label className="field">Due
                    <input id="due" type="datetime-local" value={due} required={True}
                        onChange={lambda (e: ChangeEvent) { due = e.target.value; }} />
                </label>
                <label className="field">Priority
                    <select id="priority" value={priority} onChange={lambda (e: ChangeEvent) { priority = e.target.value; }}>
                        <option value="high">High</option>
                        <option value="medium">Medium</option>
                        <option value="low">Low</option>
                    </select>
                </label>
                <label className="field">Estimate (min)
                    <input id="minutes" type="number" min="5" max="1440" step="5" value={minutes}
                        onChange={lambda (e: ChangeEvent) { minutes = e.target.value; }} />
                </label>
                <label className="field">Course / category
                    <input id="course" value={course} onChange={lambda (e: ChangeEvent) { course = e.target.value; }} />
                </label>
                <label className="field">Repeat
                    <input id="repeat" placeholder="e.g. WEEKLY:MO,WE" value={repeat}
                        onChange={lambda (e: ChangeEvent) { repeat = e.target.value; }} />
                </label>
                <label className="field wide">Notes
                    <input id="notes" value={notes} onChange={lambda (e: ChangeEvent) { notes = e.target.value; }} />
                </label>
            </div>
            <div className="row" style={{"marginTop": "12px"}}>
                <button id="save" className="btn primary" type="submit">Add task</button>
            </div>
        </form>

        <div className="panel">
            <div className="row" style={{"marginBottom": "8px"}}>
                <h2 style={{"margin": "0"}}>{"All tasks" if show_done else "Open tasks"}</h2>
                <span className="spacer"></span>
                <label className="row muted">
                    <input type="checkbox" checked={show_done}
                        onChange={lambda (e: ChangeEvent) { show_done = e.target.checked; }} />
                    show finished
                </label>
            </div>
            {if len(tasks) == 0 {
                <p className="muted">No tasks yet.</p>
            }}
            <ul className="list">
                {for t in tasks {
                    <li key={t.id}>
                        <div className="grow">
                            <b className="title-link" title="Edit task" onClick={lambda (e: MouseEvent) { open_task = t.id; }}>{t.title}</b>
                            {t.category and <span className="tag">{t.category}</span>}
                            {t.priority == "high" and <span className="tag high">high</span>}
                            {t.status == "done" and <span className="tag done">done</span>}
                            {t.status == "scheduled" and <span className="tag done">scheduled</span>}
                            {t.recurrence and <span className="tag">repeats {t.recurrence}</span>}
                            <div className="reason">due {local_label(t.due)} · {t.estimated_minutes} min{(" · " + t.notes) if t.notes else ""}</div>
                        </div>
                        {t.status != "done" and
                            <button className="btn small primary" onClick={lambda (e: MouseEvent) { mark_done(t.id); }}>Done</button>}
                        <button className="btn small" onClick={lambda (e: MouseEvent) { open_task = t.id; }}>Edit</button>
                        <button className="btn small danger" onClick={lambda (e: MouseEvent) { remove(t.id); }}>Delete</button>
                    </li>
                }}
            </ul>
        </div>
    </div>
}
