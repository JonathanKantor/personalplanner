"""One block on the calendar (used by the week grid and the agenda list).

Styles by what it is:
- class                 -> blue "Class"
- other event           -> neutral (your meetings, synced events)
- planned work / due    -> coral "Deadline", with a round checkbox that marks
                           the task done (filled terracotta, title struck, faded)
- suggested work        -> amber "Focus time" (dashed), with ✓ accept / ✗ reject

Subtitle: "10:30 – 11:30" for events, "3:00 – 4:00 · due Sat" for work,
"Due Wed · EECS 295" for a deadline.
"""

import type from core.models { DayItem }
import from ..lib.ui { time_range }
import from .kit { Icon }

def:pub style_of(it: DayItem) -> str {
    if it.kind == "class" { return "class"; }
    if it.kind == "event" { return "event"; }
    if it.kind == "deadline" { return "deadline"; }
    return "focus" if it.status == "suggested" else "deadline";
}

def:pub subtitle_of(it: DayItem) -> str {
    if it.kind == "deadline" {
        return "Due " + it.due_day + ((" · " + it.course) if it.course else "");
    }
    span = time_range(it.start_min, it.end_min);
    if it.kind == "block" {
        return span + (" · due " + it.due_day if it.due_day else "");
    }
    return span;
}

def:pub EventBlock(
    item: DayItem,
    onToggleDone: Callable[[str, bool], None],
    onAccept: Callable[[str], None],
    onReject: Callable[[str], None],
    compact: bool = False                    # short block: one line
) -> JsxElement {
    kind = style_of(item);
    checkable = kind == "deadline";
    sub = subtitle_of(item);

    def stop(e: MouseEvent) {
        e.stopPropagation();                 # don't also open the editor
    }

    <div className={"ev-body" + (" compact" if compact else "")}>
        <div className="ev-title">{item.title}</div>
        {(not compact) and <div className="ev-sub num">{sub}</div>}
        {if checkable {
            <button type="button" className={"ev-check" + (" on" if item.done else "")}
                aria-label={("Mark not done: " if item.done else "Mark done: ") + item.title}
                aria-pressed={item.done}
                onClick={lambda (e: MouseEvent) { e.stopPropagation(); onToggleDone(item.task_id, item.done); }}>
                {item.done and <Icon name="check" size={10} />}
            </button>
        } elif item.status == "suggested" {
            <div className="ev-acts" onClick={stop}>
                <button type="button" aria-label={"Accept: " + item.title} onClick={lambda (e: MouseEvent) { onAccept(item.id); }}><Icon name="check" size={12} /></button>
                <button type="button" aria-label={"Reject: " + item.title} onClick={lambda (e: MouseEvent) { onReject(item.id); }}><Icon name="x" size={12} /></button>
            </div>
        }}
    </div>
}
