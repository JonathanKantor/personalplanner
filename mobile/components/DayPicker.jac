"""Pick a date from a sideways-scrolling row: Today, Tomorrow, Wed 7, ...
(mobUI has no native date picker). A chosen date outside the row is shown
first so it stays visible."""

import from "@jac/mobui" { ScrollView, Pressable, Text }
import from ..theme { C, S, R, F }
import from ..lib { today_str, add_days, weekday, day_num }

glob DAYS_SHOWN: int = 28;

def:pub DayPicker(value: str, onChange: Callable[[str], None], testID: str = "day") -> JsxElement {
    today = today_str();
    days = [add_days(today, n) for n in range(DAYS_SHOWN)];
    if value and value not in days {
        days = [value] + days;
    }

    def label(d: str) -> str {
        if d == today { return "Today"; }
        if d == add_days(today, 1) { return "Tomorrow"; }
        return weekday(d) + " " + day_num(d);
    }

    # flexGrow 0: inside a vertical list, a sideways row must not stretch to fill it.
    <ScrollView horizontal={True} showsHorizontalScrollIndicator={False} style={{"flexGrow": 0}}
        contentContainerStyle={{"gap": S.xs, "alignItems": "center"}}>
        {[
            <Pressable key={d} testID={testID + "-" + d} onPress={lambda { onChange(d); }}
                style={{"paddingVertical": S.xs + S.xxs, "paddingHorizontal": S.md, "borderRadius": R.pill, "borderWidth": 1,
                        "borderColor": C.accent if d == value else C.borderStrong,
                        "backgroundColor": C.accentTint if d == value else C.surface}}>
                <Text style={{"fontSize": F.sm, "color": C.accentInk if d == value else C.text}}>{label(d)}</Text>
            </Pressable>
            for d in days
        ]}
    </ScrollView>
}
