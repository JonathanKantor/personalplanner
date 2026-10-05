"""/ - the week view: classes and planned blocks together, plus the
"Suggest schedule" action with accept / reject. Click a block or a due task
to edit it (TaskEditor); drag a block to move it.

Pages in the (auth) folder require login; the router redirects to /login.
"""

import from core.views { get_week_view }
import from core.planning { suggest_schedule, accept_block, reject_block, accept_all, adjust_block }
import type from core.models { WeekView, PlanView, DayItem }
import from ...components.WeekGrid { WeekGrid }
import from ...components.TaskEditor { TaskEditor }
import from ...lib.ui { error_text, hhmm }

def:pub WeekPage() -> JsxPage {
    has week: WeekView | None = None,
        plan: PlanView | None = None,      # result of the last "Suggest schedule"
        start: str = "",                   # any date in the shown week; "" = this week
        error: str = "",
        busy: bool = False,
        notice: str = "",
        # the task open in the editor ("" = closed), and the block it was opened from
        open_task: str = "",
        open_block: DayItem | None = None,
        open_date: str = "";

    async def load {
        try {
            week = await get_week_view(start);
        } except Exception as e {
            error = error_text(e);
        }
    }

    # Runs on mount and whenever `start` changes (prev/next week).
    async can with [start] entry {
        await load();
    }

    # Each action: clear the old error, call the server, show any error,
    # then reload the week so the grid reflects the change.
    def begin {
        error = "";
        busy = True;
    }

    async def finish {
        busy = False;
        await load();
    }

    async def suggest {
        begin();
        try {
            plan = await suggest_schedule(7);
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    async def accept(id: str) {
        begin();
        try {
            await accept_block(id);
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    async def reject(id: str) {
        begin();
        try {
            await reject_block(id);
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    async def accept_everything {
        begin();
        try {
            await accept_all();
            plan = None;
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    def prev_week(e: MouseEvent) {
        if week {
            start = week.prev_start;
        }
    }

    def next_week(e: MouseEvent) {
        if week {
            start = week.next_start;
        }
    }

    def open_editor(task_id: str, block: DayItem | None, day: str) {
        open_task = task_id;
        open_block = block;
        open_date = day;
    }

    """A block was dragged to `day` at start..end (minutes past midnight).
    adjust_block saves it (and accepts it if it was a suggestion); the server
    refuses moves onto classes, events or other planned blocks."""
    async def move_block(id: str, day: str, start_min: int, end_min: int) {
        begin();
        notice = "";
        try {
            b = await adjust_block(id, day + "T" + hhmm(start_min), day + "T" + hhmm(end_min));
            notice = "Moved " + b.task_title + " to " + hhmm(start_min) + ".";
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    <div>
        <div className="week-head">
            <h1>{week.label if week else "Week"}</h1>
            <button className="btn" onClick={prev_week} disabled={not week}>‹ Prev</button>
            <button className="btn" onClick={lambda (e: MouseEvent) { start = ""; }}>This week</button>
            <button className="btn" onClick={next_week} disabled={not week}>Next ›</button>
            <span className="spacer"></span>
            <button id="suggest" className="btn primary" onClick={suggest} disabled={busy}>Suggest schedule</button>
            {week and week.suggested_count > 0 and
                <button id="accept-all" className="btn" onClick={accept_everything} disabled={busy}>Accept all ({week.suggested_count})</button>}
        </div>
        <div className="legend" style={{"marginBottom": "8px"}}>
            <span className="l-class">Class</span><span className="l-event">Event</span>
            <span className="l-plan">Planned</span><span className="l-suggest">Suggested</span>
            {week and <span>Times in {week.timezone}</span>}
        </div>

        {error and <div className="error">{error}</div>}
        {notice and <div className="notice">{notice}</div>}

        {if plan and len(plan.unscheduled) > 0 {
            <div className="panel">
                <h2>Couldn't fully schedule</h2>
                <ul className="list unscheduled">
                    {for u in plan.unscheduled {
                        <li key={u.task_id}><b>{u.title}</b>: {u.reason}</li>
                    }}
                </ul>
            </div>
        }}

        {week and <WeekGrid week={week} onAccept={accept} onReject={reject}
                             onOpen={open_editor} onMove={move_block} />}

        {open_task and week and <TaskEditor taskId={open_task} tz={week.timezone}
                block={open_block} blockDate={open_date}
                onClose={lambda { open_task = ""; }} onChanged={lambda { load(); }} />}

        {if week and week.suggested_count > 0 {
            <div className="panel" style={{"marginTop": "16px"}}>
                <h2>Suggestions</h2>
                <ul className="list">
                    {for d in week.days {
                        for it in d.items {
                            if it.status == "suggested" {
                                <li key={it.id}>
                                    <div className="grow">
                                        <div><b>{it.title}</b> · {d.label} {it.start_label}-{it.end_label}</div>
                                        <div className="reason">{it.reason}</div>
                                    </div>
                                    <button className="btn small primary" onClick={lambda (e: MouseEvent) { accept(it.id); }}>Accept</button>
                                    <button className="btn small" onClick={lambda (e: MouseEvent) { open_editor(it.task_id, it, d.date); }}>Adjust</button>
                                    <button className="btn small danger" onClick={lambda (e: MouseEvent) { reject(it.id); }}>Reject</button>
                                </li>
                            }
                        }
                    }}
                </ul>
            </div>
        }}
    </div>
}
