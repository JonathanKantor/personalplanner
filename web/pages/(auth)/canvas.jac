"""/canvas - import Canvas assignments as tasks from the Canvas calendar feed.

1. Paste the feed URL (Canvas: Calendar -> "Calendar Feed") and Load.
2. Tick the assignments to import and set each one's estimate (and priority).
3. Import. Later, "Sync" refreshes due dates and shows only new assignments.
"""

import from core.canvas { canvas_sync, canvas_import, canvas_feed_url }
import from core.preferences { get_preferences }
import type from core.models { CanvasPreview, CanvasItem }
import from ...lib.ui { error_text }
import from ...components.PageHeader { PageHeader }
import from ...components.kit { Chip }

glob QUICK_MINUTES: list[int] = [30, 60, 120, 180];

"""One row of the review table (client-side state)."""
obj Row {
    has uid: str,
        title: str,
        course: str,
        due: str,
        status: str,
        picked: bool,
        minutes: str,
        priority: str;
}

def:pub CanvasPage() -> JsxPage {
    has url: str = "",
        rows: list[Row] = [],
        loaded: bool = False,
        error: str = "",
        notice: str = "",
        busy: bool = False,
        tz: str = "",
        bulk: str = "60";

    async can with entry {
        try {
            tz = (await get_preferences()).timezone;
            url = await canvas_feed_url();
        } except Exception as e {
            error = error_text(e);
        }
    }

    def due_label(iso: str) -> str {
        return new(Date, iso).toLocaleString("en-US", {  # jac:ignore[E1053]
            "timeZone": tz, "weekday": "short", "month": "short", "day": "numeric",
            "hour": "numeric", "minute": "2-digit"
        });
    }

    def to_rows(p: CanvasPreview) -> list[Row] {
        return [
            Row(uid=i.uid, title=i.title, course=i.course, due=i.due, status=i.status,
                picked=i.status == "new", minutes="60", priority="medium")
            for i in p.items
        ];
    }

    async def load {
        error = "";
        notice = "";
        busy = True;
        try {
            p = await canvas_sync(url);
            url = p.feed_url;
            rows = to_rows(p);
            loaded = True;
            fresh = len([r for r in rows if r.status == "new"]);
            notice = str(fresh) + " new assignment(s)." + (
                (" Updated " + str(p.updated) + " already-imported task(s) from Canvas.") if p.updated > 0 else ""
            );
        } except Exception as e {
            error = error_text(e);
        }
        busy = False;
    }

    """Change one field of one row. Rows are replaced, not edited in place,
    so the page re-renders (see jac-cl-components pitfalls)."""
    def edit(uid: str, field: str, value: any) {
        updated: list[Row] = [];
        for r in rows {
            if r.uid == uid {
                r2 = Row(uid=r.uid, title=r.title, course=r.course, due=r.due, status=r.status,
                         picked=r.picked, minutes=r.minutes, priority=r.priority);
                if field == "picked" { r2.picked = value; }
                elif field == "title" { r2.title = value; }
                elif field == "course" { r2.course = value; }
                elif field == "minutes" { r2.minutes = value; }
                elif field == "priority" { r2.priority = value; }
                updated.append(r2);
            } else {
                updated.append(r);
            }
        }
        rows = updated;
    }

    def apply_bulk(e: MouseEvent) {
        for r in rows {
            if r.picked {
                edit(r.uid, "minutes", bulk);
            }
        }
    }

    async def do_import {
        error = "";
        notice = "";
        choices = [
            {"uid": r.uid, "include": r.picked, "title": r.title, "course": r.course,
             "estimated_minutes": int(r.minutes or "0"), "priority": r.priority}
            for r in rows if r.status != "imported"
        ];
        busy = True;
        try {
            res = await canvas_import(choices);
            notice = "Imported " + str(res.created) + " task(s)" + ((", skipped " + str(res.dismissed) + ".") if res.dismissed > 0 else ".") + " Open Week and press Suggest schedule.";
            p = await canvas_sync("");
            rows = to_rows(p);
        } except Exception as ex {
            error = error_text(ex);
        }
        busy = False;
    }

    def status_tag(status: str) -> JsxElement {
        label = {"imported": "imported", "dismissed": "skipped before", "past_due": "past due"}.get(status, "");
        return <Chip label={label} tone={"accent" if status == "imported" else "neutral"} /> if label else <span></span>;
    }

    chosen = len([r for r in rows if r.picked and r.status != "imported"]);

    <div>
        <PageHeader eyebrow="Import" title="Canvas assignments"
                    subtitle="Bring assignments in as tasks, with your own time estimates." />
        {error and <div className="error">{error}</div>}
        {notice and <div className="notice">{notice}</div>}

        <div className="panel">
            <h2>Canvas calendar feed</h2>
            <p className="muted">In Canvas, open Calendar and click "Calendar Feed" (bottom right). Copy the link and paste it here. It's private to you, so treat it like a password.</p>
            <div className="row">
                <input id="feed-url" className="input grow" aria-label="Canvas calendar feed URL"
                    placeholder="https://umich.instructure.com/feeds/calendars/user_....ics"
                    value={url} onChange={lambda (e: ChangeEvent) { url = e.target.value; }} />
                <button id="load" className="btn primary" onClick={load} disabled={busy or not url}>{"Sync" if loaded else "Load assignments"}</button>
            </div>
        </div>

        {if loaded {
            <div className="panel">
                <div className="row mb-2">
                    <h2 className="m-0">Assignments</h2>
                    <span className="spacer"></span>
                    <span className="muted">Estimate for all ticked:</span>
                    <input type="number" min="5" max="1440" step="5" value={bulk} className="input xs" aria-label="Estimate for all ticked (minutes)"
                        onChange={lambda (e: ChangeEvent) { bulk = e.target.value; }} />
                    <button className="btn small" onClick={apply_bulk}>Apply</button>
                </div>
                {if len(rows) == 0 {
                    <p className="muted">No assignments due in the next 6 months.</p>
                }}
                <ul className="list">
                    {for r in rows {
                        <li key={r.uid} className={"imported" if r.status == "imported" else ""}>
                            <input type="checkbox" aria-label={"Import " + r.title} checked={r.picked} disabled={r.status == "imported"}
                                onChange={lambda (e: ChangeEvent) { edit(r.uid, "picked", e.target.checked); }} />
                            <div className="grow">
                                <div className="row">
                                    <input value={r.title} className="input bare grow strong" aria-label="Title"
                                        disabled={r.status == "imported"}
                                        onChange={lambda (e: ChangeEvent) { edit(r.uid, "title", e.target.value); }} />
                                    {status_tag(r.status)}
                                </div>
                                <div className="row reason">
                                    <span>due {due_label(r.due)}</span>
                                    <input value={r.course} placeholder="course" className="input sm" aria-label="Course"
                                        disabled={r.status == "imported"}
                                        onChange={lambda (e: ChangeEvent) { edit(r.uid, "course", e.target.value); }} />
                                </div>
                            </div>
                            {if r.status != "imported" {
                                <select className="input" aria-label="Priority" value={r.priority} onChange={lambda (e: ChangeEvent) { edit(r.uid, "priority", e.target.value); }}>
                                    <option value="high">High</option>
                                    <option value="medium">Medium</option>
                                    <option value="low">Low</option>
                                </select>
                                <div className="row gap-1">
                                    <input className="est input xs" aria-label="Estimate (minutes)" type="number" min="5" max="1440" step="5" value={r.minutes}
                                        onChange={lambda (e: ChangeEvent) { edit(r.uid, "minutes", e.target.value); }} />
                                    <span className="muted">min</span>
                                    {for m in QUICK_MINUTES {
                                        <button key={str(m)} className={"btn small" + (" primary" if r.minutes == str(m) else "")}
                                            onClick={lambda (e: MouseEvent) { edit(r.uid, "minutes", str(m)); }}>{str(m)}</button>
                                    }}
                                </div>
                            }}
                        </li>
                    }}
                </ul>
                <div className="row mt-3">
                    <button id="import" className="btn primary" onClick={do_import} disabled={busy or chosen == 0}>Import {str(chosen)} task(s)</button>
                    <span className="muted">Unticked assignments are remembered as skipped. Due dates always come from Canvas.</span>
                </div>
            </div>
        }}
    </div>
}
