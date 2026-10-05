"""The 7-day calendar grid.

All times come pre-computed in the user's timezone from the server
(core/views.jac: minutes past midnight), so this component does no date math.

Interaction:
- Click a work block, a deadline, or one of your own events to edit it.
- Drag a work block or one of your own events to another time or day
  (HTML drag-and-drop): snaps to 15 minutes, keeps its length.
- Round checkbox on work/deadline blocks marks the task done.
Classes, synced events and deadlines are fixed (not draggable).
"""

import from "react" { useEffect }
import type from core.models { WeekView, DayView, DayItem }
import from ..lib.ui { hour_label, now_minutes, time_range }
import from .EventBlock { EventBlock, style_of, subtitle_of }

glob HOUR_PX: int = 48,                  # keep in sync with --hour in tokens.css
     SNAP: int = 15,                     # minutes
     DEFAULT_LO: int = 8 * 60,           # 8AM
     DEFAULT_HI: int = 20 * 60,          # 8PM
     DEADLINE_LEN: int = 45;             # drawn height of a deadline marker (minutes)

def:pub WeekGrid(
    week: WeekView,
    tz: str,
    onAccept: Callable[[str], None],
    onReject: Callable[[str], None],
    onToggleDone: Callable[[str, bool], None],
    onOpen: Callable[[str, DayItem | None, str], None],    # (task id, block or None, date)
    onOpenEvent: Callable[[DayItem, str], None],           # (your event, date)
    onMove: Callable[[str, str, str, int, int], None]     # (id, "block"|"event", date, start min, end min)
) -> JsxElement {
    has drag_id: str = "",
        drag_kind: str = "",
        drag_len: int = 0,
        drag_grab: int = 0,
        drop_day: str = "",
        drop_min: int = -1,
        now_min: int = now_minutes(tz);

    # Move the "now" line every minute. (A timer handle created in an effect
    # must be cleared in the same effect, hence useEffect - see jac-cl-components.)
    useEffect(lambda {
        timer = setInterval(lambda { now_min = now_minutes(tz); }, 60000);
        return lambda { clearInterval(timer); };
    }, [tz]);

    # Visible hours: 8AM-8PM, widened to fit any class/event/work block.
    lo = DEFAULT_LO;
    hi = DEFAULT_HI;
    for d in week.days {
        for it in d.items {
            if not it.all_day and it.kind != "deadline" {
                lo = min(lo, it.start_min);
                hi = max(hi, it.end_min);
            }
        }
    }
    lo = (lo // 60) * 60;
    hi = ((hi + 59) // 60) * 60;
    height = (hi - lo) * HOUR_PX // 60;
    hours = [h for h in range(lo, hi + 60, 60)];

    """Where an item is drawn (start, end minutes). Deadlines are a short
    block ending at the due time; ones due outside the visible hours sit at
    the top or bottom edge (their subtitle still says when they're due)."""
    def span(it: DayItem) -> tuple[int, int] {
        if it.kind != "deadline" {
            return (it.start_min, it.end_min);
        }
        end = max(lo + DEADLINE_LEN, min(it.end_min, hi));
        return (end - DEADLINE_LEN, end);
    }

    """Side-by-side lanes for overlapping items in one day: returns
    {item id: (lane, lanes in its overlap group)}. Items are taken in start
    order; each goes in the first lane that's free, and every item in a group
    of mutually overlapping items gets the same width."""
    def lanes(items: list[DayItem]) -> dict {
        timed = sorted([it for it in items if not it.all_day], key=lambda (it: DayItem) { span(it)[0]; });
        out: dict = {};
        group: list[DayItem] = [];
        lane_ends: list[int] = [];
        group_end = -1;
        for it in timed {
            (s, e) = span(it);
            if s >= group_end and group {
                for g in group { out[g.id] = (out[g.id][0], len(lane_ends)); }
                group = [];
                lane_ends = [];
            }
            lane = 0;
            while lane < len(lane_ends) and lane_ends[lane] > s {
                lane += 1;
            }
            if lane == len(lane_ends) { lane_ends = lane_ends + [e]; }
            else { lane_ends[lane] = e; }
            out[it.id] = (lane, 1);
            group = group + [it];
            group_end = max(group_end, e);
        }
        for g in group { out[g.id] = (out[g.id][0], len(lane_ends)); }
        return out;
    }

    def box_style(start: int, end: int, lane: int = 0, count: int = 1) -> dict {
        top = (max(start, lo) - lo) * HOUR_PX // 60;
        h = max(20, (min(end, hi) - max(start, lo)) * HOUR_PX // 60 - 3);
        # inside the column's side padding, split into `count` equal lanes
        width = "(100% - 2 * var(--space-1)) / " + str(count);
        return {
            "top": str(top) + "px", "height": str(h) + "px",
            "left": "calc(var(--space-1) + " + width + " * " + str(lane) + ")",
            "width": "calc(" + width + " - 2px)", "right": "auto"
        };
    }

    def movable(it: DayItem) -> bool {
        return it.kind == "block" or it.editable;
    }

    # ---- drag and drop (browser drag events are untyped: any)
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

    def open_item(it: DayItem, day: str) {
        if it.kind == "block" { onOpen(it.task_id, it, day); }
        elif it.kind == "deadline" { onOpen(it.task_id, None, day); }
        elif it.editable { onOpenEvent(it, day); }
    }

    day_lanes = {d.date: lanes(d.items) for d in week.days};

    <div className="cal-grid" role="grid" aria-label="Week calendar">
        {#* header row: weekday + date number *#}
        <div className="cal-corner"></div>
        {for d in week.days {
            <div key={d.date} className={"cal-dayhead" + (" today" if d.is_today else "") + (" off" if d.is_day_off else "")}>
                <div className="cal-weekday">{d.label[0:3]}</div>
                <div className="cal-daynum num">{d.date[8:10].lstrip("0")}</div>
                {for it in d.items {
                    if it.all_day { <div key={it.id} className="cal-allday" title={it.title}>{it.title}</div> }
                }}
            </div>
        }}

        {#* hour labels *#}
        <div className="cal-gutter" style={{"height": str(height) + "px"}}>
            {for h in hours {
                <div key={str(h)} className="cal-hour num" style={{"top": str((h - lo) * HOUR_PX // 60) + "px"}}>{hour_label(h)}</div>
            }}
        </div>

        {#* one column per day; columns accept dropped blocks *#}
        {for d in week.days {
            <div key={d.date}
                 className={"cal-col" + (" off" if d.is_day_off else "") + (" drop" if drop_day == d.date else "")}
                 style={{"height": str(height) + "px"}}
                 onDragOver={lambda (e: any) { drag_over(e, d.date); }}
                 onDrop={lambda (e: any) { drop(e, d.date); }}>
                {for it in d.items {
                    if not it.all_day {
                        (s, e) = span(it);
                        (lane, count) = day_lanes[d.date][it.id];
                        <div key={it.id}
                             className={"ev " + style_of(it) + (" movable" if movable(it) else "") + (" clickable" if (movable(it) or it.kind == "deadline") else "")
                                        + (" done" if it.done else "") + (" suggested" if it.status == "suggested" else "") + (" dragging" if drag_id == it.id else "")}
                             style={box_style(s, e, lane, count)}
                             draggable={movable(it)}
                             onDragStart={lambda (ev: any) { start_drag(ev, it); }}
                             onDragEnd={lambda (ev: any) { end_drag(); }}
                             onClick={lambda (ev: MouseEvent) { open_item(it, d.date); }}
                             title={it.title + " · " + subtitle_of(it) + ("\n" + it.reason if it.reason else "")}>
                            <EventBlock item={it} compact={(e - s) < 40 or count > 1} oneLine={(e - s) < 75}
                                onToggleDone={onToggleDone} onAccept={onAccept} onReject={onReject} />
                        </div>
                    }
                }}
                {#* current time, only on today's column *#}
                {(d.is_today and lo <= now_min and now_min <= hi) and
                    <div className="cal-now" style={{"top": str((now_min - lo) * HOUR_PX // 60) + "px"}} aria-hidden="true"></div>}
                {#* where the dragged block would land *#}
                {(drop_day == d.date and drop_min >= 0) and
                    <div className="ev ghost num" style={box_style(drop_min, drop_min + drag_len)}>{time_range(drop_min, drop_min + drag_len)}</div>}
            </div>
        }}
    </div>
}
