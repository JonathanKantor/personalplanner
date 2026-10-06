"""One item of a day, styled like the web calendar's blocks:

- class                 -> blue
- other event           -> neutral (your meetings, synced events)
- planned work / due    -> coral, with a round checkbox that finishes the task
- suggested work        -> dashed amber "focus time", with ✓ accept / ✗ reject

Subtitle: "10:30 – 11:30" for events, "3:00 – 4:00 · due Sat" for work,
"Due Wed · EECS 295 · 11:59pm" for a deadline.
"""

import from "@jac/mobui" { View, Text, Pressable }
import type from core.models { DayItem }
import from ..theme { C, S, R, F, Z, kind_colors, styles }
import from ..lib { time_range, clock12, clock_ampm }
import from .kit { CheckCircle }
import from .Icon { Icon }

def:pub style_of(it: DayItem) -> str {
    if it.kind == "class" or it.kind == "event" or it.kind == "deadline" { return it.kind; }
    return "focus" if it.status == "suggested" else "deadline";
}

def:pub subtitle_of(it: DayItem) -> str {
    if it.kind == "deadline" {
        return "Due " + it.due_day + ((" · " + it.course) if it.course else "") + " · " + clock_ampm(it.end_min);
    }
    span = time_range(it.start_min, it.end_min);
    return span + ((" · due " + it.due_day) if it.kind == "block" and it.due_day else "");
}

def:pub EventRow(
    item: DayItem,
    onOpen: Callable[[DayItem], None],
    onToggleDone: Callable[[str, bool], None],
    onAccept: Callable[[str], None],
    onReject: Callable[[str], None]
) -> JsxElement {
    kind = style_of(item);
    col = kind_colors(kind);
    suggested = item.status == "suggested";
    tappable = item.kind == "block" or item.kind == "deadline" or item.editable;
    box = {
        "flexDirection": "row", "alignItems": "center", "gap": S.md,
        "backgroundColor": col.bg, "borderRadius": R.block,
        "borderLeftWidth": 3, "borderLeftColor": col.border,
        "borderWidth": 1 if suggested else 0, "borderColor": col.border,
        "borderStyle": "dashed" if suggested else "solid",
        "paddingVertical": S.sm + S.xxs, "paddingHorizontal": S.md,
        "opacity": 0.55 if item.done else 1.0
    };
    action = {"padding": S.xs + S.xxs, "borderRadius": R.pill, "backgroundColor": C.surface};

    <Pressable testID={"item-" + item.id} style={box} disabled={not tappable} onPress={lambda { onOpen(item); }}>
        <Text style={{"width": Z.timeCol, "color": col.text, "fontSize": F.sm, "fontWeight": "600"}}>
            {("Due") if item.kind == "deadline" else clock12(item.start_min)}
        </Text>
        <View style={{"flex": 1, "gap": S.xxs}}>
            <Text numberOfLines={2} style={{"color": col.text, "fontSize": F.md, "fontWeight": "600",
                "textDecorationLine": "line-through" if item.done else "none"}}>{item.title}</Text>
            <Text numberOfLines={1} style={{"color": col.text, "opacity": 0.8, "fontSize": F.xs}}>{subtitle_of(item)}</Text>
        </View>
        {(
            <View style={styles.row}>
                <Pressable testID={"accept-" + item.id} style={action} onPress={lambda { onAccept(item.id); }} accessibilityLabel={"Accept: " + item.title}>
                    <Icon name="check" size={F.md} color={C.success}/>
                </Pressable>
                <Pressable testID={"reject-" + item.id} style={action} onPress={lambda { onReject(item.id); }} accessibilityLabel={"Reject: " + item.title}>
                    <Icon name="x" size={F.md} color={C.danger}/>
                </Pressable>
            </View>
        ) if suggested else (
            (<CheckCircle testID={"done-" + item.id} checked={item.done}
                label={("Mark not done: " if item.done else "Mark done: ") + item.title}
                onToggle={lambda { onToggleDone(item.task_id, item.done); }}/>) if kind == "deadline" else <View/>
        )}
    </Pressable>
}
