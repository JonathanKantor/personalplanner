"""Add / edit one of your own events (meetings etc. not in Google Calendar).

With `item` = None it creates a new event (optionally weekly, optionally a
class); with an item it edits or deletes that occurrence (or its whole series).
"""

import from core.events { create_event, update_event, delete_event }
import type from core.models { DayItem }
import from ..lib.ui { error_text, hhmm }

def:pub EventEditor(
    day: str,
    onClose: Callable[[], None],
    onChanged: Callable[[str], None],          # gets a message for the page
    item: DayItem | None = None
) -> JsxElement {
    has title: str = item.title if item else "",
        date: str = day,
        start: str = hhmm(item.start_min) if item else "09:00",
        end: str = hhmm(item.end_min) if item else "10:00",
        weekly: bool = False,
        weeks: str = "10",
        is_class: bool = False,
        error: str = "",
        busy: bool = False;

    """After saving, warn if the event overlaps blocks you had already planned
    (those never move on their own)."""
    def message(verb: str, conflicts: list[str]) -> str {
        msg = verb + " '" + title.strip() + "'.";
        if len(conflicts) > 0 {
            msg = msg + " It overlaps your planned " + ", ".join(conflicts) + ": drag or remove that block.";
        }
        return msg;
    }

    async def save {
        error = "";
        busy = True;
        try {
            if item {
                r = await update_event(item.id, {"title": title, "day": date, "start": start, "end": end});
                onChanged(message("Updated", r.conflicts));
            } else {
                r = await create_event(title, date, start, end, is_class, int(weeks or "1") if weekly else 1);
                onChanged(message("Added" + ((" " + str(len(r.events)) + " weekly") if len(r.events) > 1 else ""), r.conflicts));
            }
            onClose();
        } except Exception as e {
            error = error_text(e);
        }
        busy = False;
    }

    async def remove(whole_series: bool) {
        if not item {
            return;
        }
        error = "";
        try {
            n = await delete_event(item.id, whole_series);
            onChanged("Deleted " + str(n) + " event" + ("s" if n != 1 else "") + ".");
            onClose();
        } except Exception as e {
            error = error_text(e);
        }
    }

    def stop(e: MouseEvent) {
        e.stopPropagation();
    }

    <div className="modal-backdrop" onClick={lambda (e: MouseEvent) { onClose(); }}>
        <div className="modal panel" onClick={stop}>
            <div className="row" style={{"marginBottom": "8px"}}>
                <h2 style={{"margin": "0"}}>{"Edit event" if item else "Add event"}</h2>
                <span className="spacer"></span>
                <button className="btn small" onClick={lambda (e: MouseEvent) { onClose(); }}>Close</button>
            </div>
            <p className="muted" style={{"marginTop": "0"}}>Meetings and other commitments that aren't in Google Calendar. The planner schedules around them.</p>
            {error and <div className="error">{error}</div>}
            <div className="form-grid">
                <label className="field wide">Title
                    <input id="event-title" value={title} placeholder="e.g. Advisor meeting"
                        onChange={lambda (e: ChangeEvent) { title = e.target.value; }} />
                </label>
                <label className="field">Date
                    <input id="event-date" type="date" value={date} onChange={lambda (e: ChangeEvent) { date = e.target.value; }} />
                </label>
                <label className="field">From
                    <input id="event-start" type="time" value={start} onChange={lambda (e: ChangeEvent) { start = e.target.value; }} />
                </label>
                <label className="field">To
                    <input id="event-end" type="time" value={end} onChange={lambda (e: ChangeEvent) { end = e.target.value; }} />
                </label>
            </div>
            {if not item {
                <div className="row" style={{"marginTop": "12px"}}>
                    <label className="row">
                        <input id="event-weekly" type="checkbox" checked={weekly} onChange={lambda (e: ChangeEvent) { weekly = e.target.checked; }} />
                        Repeat weekly for
                    </label>
                    <input type="number" min="2" max="30" value={weeks} style={{"width": "60px"}} disabled={not weekly}
                        onChange={lambda (e: ChangeEvent) { weeks = e.target.value; }} />
                    <span className="muted">weeks</span>
                    <span className="spacer"></span>
                    <label className="row">
                        <input type="checkbox" checked={is_class} onChange={lambda (e: ChangeEvent) { is_class = e.target.checked; }} />
                        Counts as a class
                    </label>
                </div>
            }}
            <div className="row" style={{"marginTop": "12px"}}>
                <button id="event-save" className="btn primary" onClick={save} disabled={busy or not title.strip()}>{"Save" if item else "Add event"}</button>
                <span className="spacer"></span>
                {item and <button className="btn danger" onClick={lambda (e: MouseEvent) { remove(False); }}>Delete</button>}
                {item and <button className="btn danger" onClick={lambda (e: MouseEvent) { remove(True); }} title="Every week of a repeating event">Delete all repeats</button>}
            </div>
        </div>
    </div>
}
