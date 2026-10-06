"""The week as seven day buttons (MON 5 ...), with ‹ › to change week.
Today's number sits in a terracotta circle; the selected day is outlined.
A dot under a day means something is planned or due."""

import from "@jac/mobui" { View, Text, Pressable }
import type from core.models { WeekView }
import from ..theme { C, S, R, F, styles }
import from ..lib { day_num }
import from .Icon { Icon }

def:pub WeekStrip(
    week: WeekView,
    selected: str,
    onSelect: Callable[[str], None],
    onPrev: Callable[[], None],
    onNext: Callable[[], None]
) -> JsxElement {
    arrow = {"padding": S.xs, "borderRadius": R.control, "borderWidth": 1, "borderColor": C.borderStrong, "backgroundColor": C.surface};

    <View style={{"gap": S.sm}}>
        <View style={styles.row}>
            <Pressable testID="prev-week" style={arrow} onPress={onPrev} accessibilityLabel="Previous week">
                <Icon name="left" size={F.lg} color={C.text}/>
            </Pressable>
            <Text style={{"flex": 1, "textAlign": "center", "color": C.text, "fontSize": F.md, "fontWeight": "600"}}>
                {week.label.replace(" - ", " – ")} <Text style={{"color": C.subtle, "fontWeight": "400"}}>{week.start[0:4]}</Text>
            </Text>
            <Pressable testID="next-week" style={arrow} onPress={onNext} accessibilityLabel="Next week">
                <Icon name="right" size={F.lg} color={C.text}/>
            </Pressable>
        </View>
        <View style={{"flexDirection": "row", "gap": S.xs}}>
            {[
                <Pressable key={d.date} testID={"day-" + d.date} onPress={lambda { onSelect(d.date); }}
                    style={{"flex": 1, "alignItems": "center", "gap": S.xs, "paddingVertical": S.sm,
                            "borderRadius": R.control, "borderWidth": 1,
                            "borderColor": C.accent if d.date == selected else "transparent",
                            "backgroundColor": C.surface if d.date == selected else "transparent"}}>
                    <Text style={{"fontSize": F.xxs, "fontWeight": "600", "letterSpacing": 1,
                                  "color": C.accent if d.is_today else C.subtle}}>{d.label[0:3].upper()}</Text>
                    <View style={{"width": 28, "height": 28, "borderRadius": R.pill, "alignItems": "center", "justifyContent": "center",
                                  "backgroundColor": C.accent if d.is_today else "transparent"}}>
                        <Text style={{"fontSize": F.sm, "fontWeight": "600",
                                      "color": C.onAccent if d.is_today else (C.muted if d.is_day_off else C.text)}}>{day_num(d.date)}</Text>
                    </View>
                    <View style={{"width": 4, "height": 4, "borderRadius": R.pill,
                                  "backgroundColor": C.accent if any(it.kind != "class" and it.kind != "event" for it in d.items) else "transparent"}}/>
                </Pressable>
                for d in week.days
            ]}
        </View>
    </View>
}
