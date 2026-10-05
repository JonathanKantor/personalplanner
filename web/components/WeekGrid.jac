"""The 7-day grid: classes, other events, and planned blocks positioned by time.

All positions come from minute offsets the server already computed in the
user's timezone (core/views.jac), so this component does no date math.

Interaction:
- Click a planned/suggested block, or a "due:" label, to open its task; click
  one of your own events ("My events") to edit it.
- Drag a planned/suggested block or one of your own events to another time or
  day (HTML drag-and-drop). It snaps to 15 minutes and keeps its length; the
  parent saves the move. Synced (Google/iCal) events and classes are fixed.
"""

import type from core.models { WeekView, DayView, DayItem }
import from ..lib.ui { hhmm }

glob HOUR_PX: int = 48,                  # keep in sync with --hour in global.css
     SNAP: int = 15;                     # minutes

def:pub WeekGrid(
    week: WeekView,
    onAccept: Callable[[str], None],
    onReject: Callable[[str], None],
    onOpen: Callable[[str, DayItem | None, str], None],    # (task id, block or None, date)
    onOpenEvent: Callable[[DayItem, str], None],           # (your event, date)
    onMove: Callable[[str, str, str, int, int], None]     # (id, "block"|"event", date, start min, end min)
) -> JsxElement {
    # What is being dragged: block id, its length, and where on the block it
    # was grabbed (so the block doesn't jump under the pointer).
    has drag_id: str = "",
        drag_kind: str = "",
        drag_len: int = 0,
        drag_grab: int = 0,
        drop_day: str = "",
        drop_min: int = -1;

    # Visible range: working hours, widened to fit anything outside them.
    lo = week.work_start_min;
    hi = week.work_end_min;
    for d in week.days {
        for it in d.items {
            if not it.all_day {
                lo = min(lo, it.start_min);
                hi = max(hi, it.end_min);
            }
        }
    }
    lo = (lo // 60) * 60;                # round out to whole hours
    hi = ((hi + 59) // 60) * 60;
    height = (hi - lo) * HOUR_PX // 60;
    hours = [h for h in range(lo, hi, 60)];

    def box_style(top_min: int, end_min: int) -> dict {
        top = (max(top_min, lo) - lo) * HOUR_PX // 60;
        h = max(18, (min(end_min, hi) - max(top_min, lo)) * HOUR_PX // 60 - 2);
        return {"top": str(top) + "px", "height": str(h) + "px"};
    }

    def box_class(it: DayItem) -> str {
        short = " short" if it.end_min - it.start_min < 45 else "";   # one-line layout
        movable = " movable" if (it.kind == "block" or it.editable) else "";
        return "item " + (it.status if it.kind == "block" else it.kind) + short + movable;
    }

    """Minutes past midnight under the pointer, snapped, for a block grabbed
    `drag_grab` minutes below its top. Browser drag events are untyped (any)."""
    def pointer_minute(e: any) -> int {
        rect: any = e.currentTarget.getBoundingClientRect();
        raw: any = lo + (e.clientY - rect.top) * 60 / HOUR_PX - drag_grab;
        snapped: int = Math.round(raw / SNAP) * SNAP;  # jac:ignore[E1001]
        return max(0, min(snapped, 24 * 60 - drag_len));
    }

    def start_drag(e: any, it: DayItem) {
        rect: any = e.currentTarget.getBoundingClientRect();
        drag_id = it.id;
        drag_kind = "block" if it.kind == "block" else "event";
        drag_len = it.end_min - it.start_min;
        drag_grab = Math.round((e.clientY - rect.top) * 60 / HOUR_PX);  # jac:ignore[E1001]
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", it.id);      # required by some browsers
    }

    def drag_over(e: any, day: str) {
        if not drag_id {
            return;
        }
        e.preventDefault();                               # allows dropping here
        drop_day = day;
        drop_min = pointer_minute(e);
    }

    def drop(e: any, day: str) {
        e.preventDefault();
        if drag_id {
            start = pointer_minute(e);
            onMove(drag_id, drag_kind, day, start, start + drag_len);
        }
        end_drag();
    }

    def end_drag {
        drag_id = "";
        drop_day = "";
        drop_min = -1;
    }

    def no_bubble(e: MouseEvent) {
        e.stopPropagation();                              # ✓/✗ shouldn't also open the editor
    }

    <div className="week">
        {#* header row *#}
        <div className="dayhead"></div>
        {for d in week.days {
            <div key={d.date} className={"dayhead" + (" today" if d.is_today else "") + (" off" if d.is_day_off else "")}>
                {d.label}
                {for it in d.items {
                    if it.all_day { <div key={it.id} className="allday">{it.title}</div> }
                }}
                {for t in d.due {
                    if t.status != "done" {
                        <div key={t.id} className="due clickable" title="Edit task"
                             onClick={lambda (e: MouseEvent) { onOpen(t.id, None, d.date); }}>due: {t.title}</div>
                    }
                }}
            </div>
        }}

        {#* time gutter *#}
        <div className="gutter" style={{"height": str(height) + "px"}}>
            {for h in hours {
                <div key={str(h)} style={{"top": str((h - lo) * HOUR_PX // 60) + "px"}}>{hhmm(h)}</div>
            }}
        </div>

        {#* one column per day; columns accept dropped blocks *#}
        {for d in week.days {
            <div key={d.date}
                 className={"col" + (" off" if d.is_day_off else "") + (" drop" if drop_day == d.date else "")}
                 style={{"height": str(height) + "px"}}
                 onDragOver={lambda (e: any) { drag_over(e, d.date); }}
                 onDrop={lambda (e: any) { drop(e, d.date); }}>
                {for it in d.items {
                    if not it.all_day {
                        <div key={it.id} className={box_class(it) + (" dragging" if drag_id == it.id else "")}
                             style={box_style(it.start_min, it.end_min)}
                             draggable={it.kind == "block" or it.editable}
                             onDragStart={lambda (e: any) { start_drag(e, it); }}
                             onDragEnd={lambda (e: any) { end_drag(); }}
                             onClick={lambda (e: MouseEvent) {
                                 if it.kind == "block" { onOpen(it.task_id, it, d.date); }
                                 elif it.editable { onOpenEvent(it, d.date); }
                             }}
                             title={it.title + "\n" + it.start_label + "-" + it.end_label + ("\n" + it.reason if it.reason else "")
                                    + ("\nClick to edit, drag to move" if (it.kind == "block" or it.editable) else "")}>
                            <div className="t">{it.title}</div>
                            <div>{it.start_label}-{it.end_label}</div>
                            {if it.status == "suggested" {
                                <div className="acts" onClick={no_bubble}>
                                    <button title="Accept" onClick={lambda (e: MouseEvent) { onAccept(it.id); }}>✓</button>
                                    <button title="Reject" onClick={lambda (e: MouseEvent) { onReject(it.id); }}>✗</button>
                                </div>
                            }}
                        </div>
                    }
                }}
                {#* where the dragged block would land *#}
                {if drop_day == d.date and drop_min >= 0 {
                    <div className="item ghost" style={box_style(drop_min, drop_min + drag_len)}>
                        {hhmm(drop_min)}-{hhmm(drop_min + drag_len)}
                    </div>
                }}
            </div>
        }}
    </div>
}
