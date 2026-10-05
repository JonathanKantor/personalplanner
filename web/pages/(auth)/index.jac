"""/ - the week view: classes and planned blocks together, plus the
"Suggest schedule" action with accept / reject. Click a block or a due task
to edit it (TaskEditor); drag a block to move it.

Pages in the (auth) folder require login; the router redirects to /login.
"""

import from "react" { useEffect }
import from core.views { get_week_view, get_coming_up }
import from core.planning { suggest_schedule, accept_block, reject_block, accept_all, adjust_block }
import type from core.models { WeekView, PlanView, DayItem, ComingUpView }
import from ...components.WeekGrid { WeekGrid }
import from ...components.AgendaList { AgendaList }
import from ...components.ComingUp { ComingUp }
import from core.tasks { complete_task, update_task }
import from ...components.TaskEditor { TaskEditor }
import from ...components.EventEditor { EventEditor }
import from ...components.PageHeader { PageHeader }
import from ...components.kit { Button, Card, Icon, IconButton }
import from core.events { update_event }
import from core.planning { clear_suggestions }
import from ...lib.ui { error_text, hhmm, tz_name }

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
        open_date: str = "",
        # the event editor: open, the event (None = new) and its date
        event_open: bool = False,
        event_item: DayItem | None = None,
        event_date: str = "",
        adding_task: bool = False,           # "+ Add task" dialog open
        view: str = "week",                  # "week" grid or "agenda" list
        coming: ComingUpView | None = None;  # right-rail "Coming up" card

    async def load {
        try {
            week = await get_week_view(start);
            coming = await get_coming_up(6, start);
        } except Exception as e {
            error = error_text(e);
        }
    }

    # Runs on mount and whenever `start` changes (prev/next week).
    async can with [start] entry {
        await load();
    }

    # The floating assistant sends `morrow:changed` after it edits the plan.
    useEffect(lambda {
        def reload(e: any) { load(); }
        window.addEventListener("morrow:changed", reload);
        return lambda { window.removeEventListener("morrow:changed", reload); };
    }, [start]);

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

    def open_event(item: DayItem | None, day: str) {
        event_item = item;
        event_date = day;
        event_open = True;
    }

    def today_or_monday -> str {
        if week {
            for d in week.days {
                if d.is_today { return d.date; }
            }
            return week.start;
        }
        return "";
    }

    """Something was dragged to `day` at start..end (minutes past midnight).
    Blocks: adjust_block saves it (and accepts a suggestion); the server refuses
    moves onto classes, events or other planned blocks. Your own events:
    update_event moves just that occurrence."""
    async def move_item(id: str, kind: str, day: str, start_min: int, end_min: int) {
        begin();
        notice = "";
        try {
            if kind == "block" {
                b = await adjust_block(id, day + "T" + hhmm(start_min), day + "T" + hhmm(end_min));
                notice = "Moved " + b.task_title + " to " + hhmm(start_min) + ".";
            } else {
                r = await update_event(id, {"day": day, "start": hhmm(start_min), "end": hhmm(end_min)});
                notice = "Moved the event to " + hhmm(start_min) + "." + (
                    (" It overlaps your planned " + ", ".join(r.conflicts) + ".") if len(r.conflicts) > 0 else ""
                );
            }
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    """Round checkbox on a work/deadline block: finish the task (or un-finish it)."""
    async def toggle_done(task_id: str, done: bool) {
        begin();
        try {
            if done {
                await update_task(task_id, {"status": "todo"});
            } else {
                await complete_task(task_id);
            }
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    async def clear_all {
        begin();
        notice = "";
        try {
            n = await clear_suggestions();
            plan = None;
            notice = "Cleared " + str(n) + " suggestion" + ("s" if n != 1 else "") + ". Your planned blocks are unchanged.";
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    tz = week.timezone if week else "America/Detroit";
    year = week.start[0:4] if week else "";
    range_label = week.label.replace(" - ", " – ") if week else "";

    <div>
        <PageHeader eyebrow="Your week, in rhythm" title="A little more room to think."
                    subtitle="Classes, deadlines, and the time between them — all in one place.">
            <Button id="add-task" label="Add task" icon="plus" onClick={lambda (e: MouseEvent) { adding_task = True; }} />
            <Button id="add-event" label="Add event" icon="plus" variant="primary"
                    onClick={lambda (e: MouseEvent) { open_event(None, today_or_monday()); }} />
        </PageHeader>

        {error and <div className="error">{error}</div>}
        {notice and <div className="notice">{notice}</div>}

        <div className="planner-layout">
        <div className="planner-main">
            <Card className="cal-card">
                <div className="cal-toolbar">
                    <IconButton icon="chevron-left" label="Previous week" className="square" onClick={prev_week} />
                    <span className="cal-range">{range_label} <span className="cal-year num">{year}</span></span>
                    <IconButton icon="chevron-right" label="Next week" className="square" onClick={next_week} />
                    <Button label="Today" small={True} onClick={lambda (e: MouseEvent) { start = ""; }} />
                    <span className="spacer"></span>
                    {(week and week.suggested_count > 0) and
                        <Button id="accept-all" label={"Accept all (" + str(week.suggested_count) + ")"} small={True} onClick={lambda (e: MouseEvent) { accept_everything(); }} disabled={busy} />}
                    {(week and week.suggested_count > 0) and
                        <Button id="clear-suggestions" label="Clear" variant="ghost" small={True} onClick={lambda (e: MouseEvent) { clear_all(); }} disabled={busy} />}
                    <Button id="suggest" label="Suggest schedule" icon="sparkles" small={True} onClick={lambda (e: MouseEvent) { suggest(); }} disabled={busy} />
                    <div className="segmented" role="tablist" aria-label="Calendar view">
                        <button type="button" role="tab" aria-selected={view == "week"} className={"seg" + (" on" if view == "week" else "")}
                            onClick={lambda (e: MouseEvent) { view = "week"; }}><Icon name="grid" size={14} /> Week</button>
                        <button type="button" role="tab" aria-selected={view == "agenda"} className={"seg" + (" on" if view == "agenda" else "")}
                            onClick={lambda (e: MouseEvent) { view = "agenda"; }}><Icon name="list" size={14} /> Agenda</button>
                    </div>
                </div>

                {if not week {
                    <div className="cal-skeleton" aria-label="Loading"></div>
                } elif view == "week" {
                    <WeekGrid week={week} tz={tz} onAccept={accept} onReject={reject} onToggleDone={toggle_done}
                        onOpen={open_editor} onOpenEvent={lambda (it: DayItem, day: str) { open_event(it, day); }}
                        onMove={move_item} />
                } else {
                    <AgendaList week={week} onAccept={accept} onReject={reject} onToggleDone={toggle_done}
                        onOpen={open_editor} onOpenEvent={lambda (it: DayItem, day: str) { open_event(it, day); }} />
                }}

                <div className="cal-legend">
                    <span className="sw class">Class</span>
                    <span className="sw deadline">Deadline</span>
                    <span className="sw focus">Focus time</span>
                    <span className="spacer"></span>
                    <span>Times in {tz_name(tz)}</span>
                </div>
            </Card>

            {if plan and len(plan.unscheduled) > 0 {
                <Card className="side-card mt-4">
                    <div className="side-card-head">Couldn't fully schedule</div>
                    <ul className="list unscheduled">
                        {for u in plan.unscheduled {
                            <li key={u.task_id}><b>{u.title}</b>: {u.reason}</li>
                        }}
                    </ul>
                </Card>
            }}
        </div>
        <aside className="planner-side" aria-label="Coming up">
            <ComingUp data={coming}
                onToggleDone={lambda (id: str) { toggle_done(id, False); }}
                onOpen={lambda (id: str) { open_editor(id, None, ""); }} />
        </aside>
        </div>

        {open_task and week and <TaskEditor taskId={open_task} tz={week.timezone}
                block={open_block} blockDate={open_date}
                onClose={lambda { open_task = ""; }} onChanged={lambda { load(); }} />}

        {event_open and <EventEditor day={event_date} item={event_item}
                onClose={lambda { event_open = False; }}
                onChanged={lambda (msg: str) { notice = msg; load(); }} />}

        {adding_task and week and <TaskEditor taskId="" tz={week.timezone}
                onClose={lambda { adding_task = False; }} onChanged={lambda { load(); }} />}
    </div>
}
