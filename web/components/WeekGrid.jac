"""The 7-day grid: classes, other events, and planned blocks positioned by time.

All positions come from minute offsets the server already computed in the
user's timezone (core/views.jac), so this component does no date math.
"""

import type from core.models { WeekView, DayView, DayItem }
import from ..lib.ui { hhmm }

glob HOUR_PX: int = 48;                  # keep in sync with --hour in global.css

def:pub WeekGrid(
    week: WeekView,
    onAccept: Callable[[str], None],
    onReject: Callable[[str], None]
) -> JsxElement {
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

    def box_style(it: DayItem) -> dict {
        top = (max(it.start_min, lo) - lo) * HOUR_PX // 60;
        h = max(18, (min(it.end_min, hi) - max(it.start_min, lo)) * HOUR_PX // 60 - 2);
        return {"top": str(top) + "px", "height": str(h) + "px"};
    }

    def box_class(it: DayItem) -> str {
        short = " short" if it.end_min - it.start_min < 45 else "";   # one-line layout
        return "item " + (it.status if it.kind == "block" else it.kind) + short;
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
                    if t.status != "done" { <div key={t.id} className="due">due: {t.title}</div> }
                }}
            </div>
        }}

        {#* time gutter *#}
        <div className="gutter" style={{"height": str(height) + "px"}}>
            {for h in hours {
                <div key={str(h)} style={{"top": str((h - lo) * HOUR_PX // 60) + "px"}}>{hhmm(h)}</div>
            }}
        </div>

        {#* one column per day *#}
        {for d in week.days {
            <div key={d.date} className={"col" + (" off" if d.is_day_off else "")} style={{"height": str(height) + "px"}}>
                {for it in d.items {
                    if not it.all_day {
                        <div key={it.id} className={box_class(it)} style={box_style(it)}
                             title={it.title + "\n" + it.start_label + "-" + it.end_label + ("\n" + it.reason if it.reason else "")}>
                            <div className="t">{it.title}</div>
                            <div>{it.start_label}-{it.end_label}</div>
                            {if it.status == "suggested" {
                                <div className="acts">
                                    <button title="Accept" onClick={lambda (e: MouseEvent) { onAccept(it.id); }}>✓</button>
                                    <button title="Reject" onClick={lambda (e: MouseEvent) { onReject(it.id); }}>✗</button>
                                </div>
                            }}
                        </div>
                    }
                }}
            </div>
        }}
    </div>
}
