"""One row of the day: a class, an event, or a planned/suggested block."""

import from "@jac/mobui" { View, Text, Pressable }
import type from core.models { DayItem }
import from ..theme { C, S, R, F, styles }
import from .Icon { Icon }

def:pub ItemRow(
    item: DayItem,
    onAccept: Callable[[str], None],
    onReject: Callable[[str], None],
    onFinish: Callable[[str], None]
) -> JsxElement {
    # Colors by kind, same as the web week view.
    bg = C.classBg if item.kind == "class" else (C.eventBg if item.kind == "event" else (C.planBg if item.status == "accepted" else C.suggestBg));
    fg = C.classFg if item.kind == "class" else (C.eventFg if item.kind == "event" else (C.planFg if item.status == "accepted" else C.suggestFg));
    border = {"borderWidth": 1, "borderStyle": "dashed", "borderColor": C.suggestFg} if item.status == "suggested" else {};
    label = "Class" if item.kind == "class" else ("Event" if item.kind == "event" else ("Planned" if item.status == "accepted" else "Suggested"));
    round = {"padding": S.sm, "borderRadius": R.pill, "backgroundColor": C.surface};

    <View style={[styles.card, {"backgroundColor": bg}, border]}>
        <Text style={[styles.cardTime, {"color": fg}]}>{item.start_label}{"\n"}{item.end_label}</Text>
        <View style={{"flex": 1, "gap": 2}}>
            <Text style={[styles.cardTitle, {"color": fg, "fontWeight": "600"}]}>{item.title}</Text>
            <Text style={[styles.cardSub, {"color": fg}]}>{label}{(" · " + item.reason) if item.status == "suggested" and item.reason else ""}</Text>
        </View>
        {(
            <View style={styles.row}>
                <Pressable testID={"accept-" + item.id} style={round} onPress={lambda { onAccept(item.id); }}>
                    <Icon name="check" size={F.md} color={C.planFg}/>
                </Pressable>
                <Pressable testID={"reject-" + item.id} style={round} onPress={lambda { onReject(item.id); }}>
                    <Icon name="x" size={F.md} color={C.danger}/>
                </Pressable>
            </View>
        ) if item.status == "suggested" else (
            (
                <Pressable testID={"finish-" + item.task_id} style={round} onPress={lambda { onFinish(item.task_id); }}>
                    <Icon name="circle" size={F.md} color={C.planFg}/>
                </Pressable>
            ) if item.status == "accepted" else <View/>
        )}
    </View>
}
