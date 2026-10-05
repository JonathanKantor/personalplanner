"""/ - the week view: classes and planned blocks together, plus the
"Suggest schedule" action with accept / reject / adjust.

Pages in the (auth) folder require login; the router redirects to /login.
"""

import from core.views { get_week_view }
import from core.planning { suggest_schedule, accept_block, reject_block, accept_all, adjust_block }
import type from core.models { WeekView, PlanView, DayItem }
import from ...components.WeekGrid { WeekGrid }
import from ...lib.ui { error_text, hhmm }

def:pub WeekPage() -> JsxPage {
    has week: WeekView | None = None,
        plan: PlanView | None = None,      # result of the last "Suggest schedule"
        start: str = "",                   # any date in the shown week; "" = this week
        error: str = "",
        busy: bool = False,
        editing: str = "",                 # id of the suggestion being adjusted
        edit_date: str = "",
        edit_start: str = "",
        edit_end: str = "";

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

    def begin_edit(day: str, it: DayItem) {
        editing = it.id;
        edit_date = day;
        # "2:30pm" labels aren't input-friendly; rebuild HH:MM from minutes.
        edit_start = hhmm(it.start_min);
        edit_end = hhmm(it.end_min);
    }

    async def save_edit {
        begin();
        try {
            await adjust_block(editing, edit_date + "T" + edit_start, edit_date + "T" + edit_end);
            editing = "";
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

        {week and <WeekGrid week={week} onAccept={accept} onReject={reject} />}

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
                                        {if editing == it.id {
                                            <div className="row" style={{"marginTop": "6px"}}>
                                                <input type="date" value={edit_date} onChange={lambda (e: ChangeEvent) { edit_date = e.target.value; }} />
                                                <input type="time" value={edit_start} onChange={lambda (e: ChangeEvent) { edit_start = e.target.value; }} />
                                                to
                                                <input type="time" value={edit_end} onChange={lambda (e: ChangeEvent) { edit_end = e.target.value; }} />
                                                <button className="btn small primary" onClick={save_edit}>Save</button>
                                                <button className="btn small" onClick={lambda (e: MouseEvent) { editing = ""; }}>Cancel</button>
                                            </div>
                                        }}
                                    </div>
                                    <button className="btn small primary" onClick={lambda (e: MouseEvent) { accept(it.id); }}>Accept</button>
                                    <button className="btn small" onClick={lambda (e: MouseEvent) { begin_edit(d.date, it); }}>Adjust</button>
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
