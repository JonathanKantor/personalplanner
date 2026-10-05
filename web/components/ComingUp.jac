"""Right-rail "Coming up" card: open tasks soonest first, each with a round
checkbox (marks it done), title, "Due Wed · EECS 295", and a date chip; then
the week's follow-through (done / due this week) with a thin progress bar.

Data comes from the server (get_coming_up); this component only draws it.
"""

import from "@jac/runtime" { Link }
import type from core.models { ComingUpView, UpcomingItem }
import from .kit { Card, Icon, Chip, CheckCircle }

def:pub ComingUp(
    data: ComingUpView | None,
    onToggleDone: Callable[[str], None],
    onOpen: Callable[[str], None]
) -> JsxElement {
    def subtitle(it: UpcomingItem) -> str {
        return ("Overdue · " if it.overdue else "Due ") + it.due_day + ((" · " + it.course) if it.course else "");
    }

    pct = (100 * data.week_done // data.week_total) if (data and data.week_total > 0) else 0;

    <Card className="side-card coming-up">
        <div className="side-card-head">
            <Icon name="cap" size={18} />
            <span>Coming up</span>
            <span className="count num">{(str(data.open_count) + " open") if data else ""}</span>
        </div>

        {if not data {
            <div className="cu-skeleton" aria-label="Loading">
                {for i in [1, 2, 3] { <div key={str(i)} className="skeleton-row"></div> }}
            </div>
        } elif len(data.items) == 0 {
            <p className="cu-empty">Nothing coming up. Enjoy the room to think.</p>
        } else {
            <ul className="item-list">
                {for it in data.items {
                    <li key={it.id} className="item-row">
                        <CheckCircle checked={False} label={"Mark done: " + it.title}
                            onToggle={lambda { onToggleDone(it.id); }} />
                        <button type="button" className="item-main" onClick={lambda (e: MouseEvent) { onOpen(it.id); }}>
                            <span className="item-title">{it.title}</span>
                            <span className={"item-sub" + (" overdue" if it.overdue else "")}>{subtitle(it)}</span>
                        </button>
                        <Chip label={it.date_chip} tone={"danger" if it.overdue else "accent"} />
                    </li>
                }}
            </ul>
            if data.open_count > len(data.items) {
                <Link to="/tasks" className="cu-more">View all {str(data.open_count)} tasks</Link>
            }
        }}

        {if data {
            <div className="cu-footer">
                <div className="row">
                    <span className="cu-label">Weekly follow-through</span>
                    <span className="spacer"></span>
                    <span className="cu-score num">{str(data.week_done)}/{str(data.week_total)}</span>
                </div>
                <div className="cu-bar" role="progressbar" aria-label="Weekly follow-through"
                     aria-valuemin={0} aria-valuemax={data.week_total} aria-valuenow={data.week_done}>
                    <div className="cu-bar-fill" style={{"width": str(pct) + "%"}}></div>
                </div>
            </div>
        }}
    </Card>
}
