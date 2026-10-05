"""Agenda view: the same week as a simple list, grouped by day."""

import type from core.models { WeekView, DayItem }
import from .EventBlock { EventBlock, style_of }

def:pub AgendaList(
    week: WeekView,
    onAccept: Callable[[str], None],
    onReject: Callable[[str], None],
    onToggleDone: Callable[[str, bool], None],
    onOpen: Callable[[str, DayItem | None, str], None],
    onOpenEvent: Callable[[DayItem, str], None]
) -> JsxElement {
    def open_item(it: DayItem, day: str) {
        if it.kind == "block" { onOpen(it.task_id, it, day); }
        elif it.kind == "deadline" { onOpen(it.task_id, None, day); }
        elif it.editable { onOpenEvent(it, day); }
    }

    <div className="agenda">
        {for d in week.days {
            <section key={d.date} className={"agenda-day" + (" today" if d.is_today else "")}>
                <h3 className="agenda-dayhead">
                    <span className="cal-weekday">{d.label[0:3]}</span>
                    <span className="cal-daynum num">{d.date[8:10].lstrip("0")}</span>
                </h3>
                {if len(d.items) == 0 {
                    <p className="agenda-empty">Nothing scheduled</p>
                }}
                {for it in d.items {
                    <div key={it.id}
                         className={"ev agenda-row " + style_of(it) + (" done" if it.done else "") + (" suggested" if it.status == "suggested" else "")}
                         onClick={lambda (e: MouseEvent) { open_item(it, d.date); }}>
                        <EventBlock item={it} onToggleDone={onToggleDone} onAccept={onAccept} onReject={onReject} />
                    </div>
                }}
            </section>
        }}
    </div>
}
