"""Edit-task dialog, opened by clicking a task (or one of its blocks).

Edits the task itself (title, due, estimate, priority, course, notes; mark
done; delete). If opened from a block in the week grid, it also has that
block's actions: accept / reject a suggestion, change its time, or remove a
planned block from the calendar.
"""

import from core.tasks { get_task, update_task, complete_task, delete_task }
import from core.planning { accept_block, reject_block, adjust_block }
import type from core.models { TaskView, DayItem }
import from ..lib.ui { error_text, hhmm, local_input }

def:pub TaskEditor(
    taskId: str,
    tz: str,
    onClose: Callable[[], None],
    onChanged: Callable[[], None],
    block: DayItem | None = None,
    blockDate: str = ""
) -> JsxElement {
    has task: TaskView | None = None,
        error: str = "",
        busy: bool = False,
        confirm_delete: bool = False,
        title: str = "",
        due: str = "",
        priority: str = "medium",
        minutes: str = "60",
        course: str = "",
        notes: str = "",
        b_date: str = "",
        b_start: str = "",
        b_end: str = "";

    # Load the task when the dialog opens.
    async can with entry {
        try {
            t = await get_task(taskId);
            task = t;
            title = t.title;
            due = local_input(t.due, tz);
            priority = t.priority;
            minutes = str(t.estimated_minutes);
            course = t.category;
            notes = t.notes;
            if block {
                b_date = blockDate;
                b_start = hhmm(block.start_min);
                b_end = hhmm(block.end_min);
            }
        } except Exception as e {
            error = error_text(e);
        }
    }

    """Run a server action; on success refresh the page and close."""
    async def act(action: str) {
        error = "";
        busy = True;
        try {
            if action == "save" {
                await update_task(taskId, {
                    "title": title, "due": due, "priority": priority,
                    "estimated_minutes": int(minutes or "0"), "category": course, "notes": notes
                });
            } elif action == "done" {
                await complete_task(taskId);
            } elif action == "delete" {
                await delete_task(taskId);
            } elif action == "accept" and block {
                await accept_block(block.id);
            } elif action == "reject" and block {
                await reject_block(block.id);          # also "remove from calendar"
            } elif action == "move" and block {
                await adjust_block(block.id, b_date + "T" + b_start, b_date + "T" + b_end);
            }
            busy = False;
            onChanged();
            onClose();
        } except Exception as e {
            busy = False;
            error = error_text(e);
        }
    }

    def stop(e: MouseEvent) {
        e.stopPropagation();                         # clicks inside don't close the dialog
    }

    <div className="modal-backdrop" onClick={lambda (e: MouseEvent) { onClose(); }}>
        <div className="modal panel" onClick={stop}>
            <div className="row" style={{"marginBottom": "var(--space-2)"}}>
                <h2 style={{"margin": "0"}}>Edit task</h2>
                <span className="spacer"></span>
                <button className="btn small" onClick={lambda (e: MouseEvent) { onClose(); }}>Close</button>
            </div>
            {error and <div className="error">{error}</div>}
            {if not task {
                <p className="muted">{"" if error else "Loading..."}</p>
            } else {
                <div>
                    {if block {
                        <div className={"block-box " + block.status}>
                            <div><b>{"Suggested" if block.status == "suggested" else "Planned"}</b> {block.start_label}-{block.end_label}</div>
                            {block.reason and <div className="reason">{block.reason}</div>}
                            <div className="row" style={{"marginTop": "var(--space-2)"}}>
                                <input type="date" value={b_date} onChange={lambda (e: ChangeEvent) { b_date = e.target.value; }} />
                                <input type="time" value={b_start} onChange={lambda (e: ChangeEvent) { b_start = e.target.value; }} />
                                to
                                <input type="time" value={b_end} onChange={lambda (e: ChangeEvent) { b_end = e.target.value; }} />
                                <button className="btn small" onClick={lambda (e: MouseEvent) { act("move"); }} disabled={busy}>Change time</button>
                            </div>
                            <div className="row" style={{"marginTop": "var(--space-2)"}}>
                                {(block.status == "suggested") and <button className="btn small primary" onClick={lambda (e: MouseEvent) { act("accept"); }} disabled={busy}>Accept</button>}
                                <button className="btn small danger" onClick={lambda (e: MouseEvent) { act("reject"); }} disabled={busy}>
                                    {"Reject" if block.status == "suggested" else "Remove from calendar"}
                                </button>
                                <span className="muted" style={{"fontSize": "var(--text-sm)"}}>Tip: you can also drag blocks in the week grid.</span>
                            </div>
                        </div>
                    }}
                    <div className="form-grid" style={{"marginTop": "var(--space-3)"}}>
                        <label className="field wide">Title
                            <input id="edit-title" value={title} onChange={lambda (e: ChangeEvent) { title = e.target.value; }} />
                        </label>
                        <label className="field">Due
                            <input id="edit-due" type="datetime-local" value={due} onChange={lambda (e: ChangeEvent) { due = e.target.value; }} />
                        </label>
                        <label className="field">Estimate (min)
                            <input id="edit-minutes" type="number" min="5" max="1440" step="5" value={minutes}
                                onChange={lambda (e: ChangeEvent) { minutes = e.target.value; }} />
                        </label>
                        <label className="field">Priority
                            <select value={priority} onChange={lambda (e: ChangeEvent) { priority = e.target.value; }}>
                                <option value="high">High</option>
                                <option value="medium">Medium</option>
                                <option value="low">Low</option>
                            </select>
                        </label>
                        <label className="field">Course / category
                            <input value={course} onChange={lambda (e: ChangeEvent) { course = e.target.value; }} />
                        </label>
                        <label className="field wide">Notes
                            <input value={notes} onChange={lambda (e: ChangeEvent) { notes = e.target.value; }} />
                        </label>
                    </div>
                    <div className="row" style={{"marginTop": "var(--space-3)"}}>
                        <button id="edit-save" className="btn primary" onClick={lambda (e: MouseEvent) { act("save"); }} disabled={busy}>Save</button>
                        {(task.status != "done") and <button className="btn" onClick={lambda (e: MouseEvent) { act("done"); }} disabled={busy}>Mark done</button>}
                        <span className="spacer"></span>
                        {(
                            <button className="btn danger" onClick={lambda (e: MouseEvent) { act("delete"); }} disabled={busy}>Really delete?</button>
                        ) if confirm_delete else (
                            <button className="btn danger" onClick={lambda (e: MouseEvent) { confirm_delete = True; }}>Delete task</button>
                        )}
                    </div>
                </div>
            }}
        </div>
    </div>
}
