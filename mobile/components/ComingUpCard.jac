"""The "Coming up" card: open tasks soonest first, each with a round
checkbox, title, "Due Wed · EECS 295" and a date chip; then the week's
follow-through (done / due this week) with a thin progress bar."""

import from "@jac/mobui" { View, Text, Pressable }
import type from core.models { ComingUpView }
import from ..theme { C, S, R, F, styles }
import from .kit { Card, Chip, CheckCircle }
import from .Icon { Icon }

def:pub ComingUpCard(
    data: ComingUpView | None,
    onDone: Callable[[str], None],
    onOpen: Callable[[str], None]
) -> JsxElement {
    pct = (100 * data.week_done // data.week_total) if (data and data.week_total > 0) else 0;

    <Card>
        <View style={styles.row}>
            <Icon name="cap" size={F.lg} color={C.text}/>
            <Text style={[styles.cardTitle, {"flex": 1}]}>Coming up</Text>
            <Text style={{"color": C.subtle, "fontSize": F.xs}}>{(str(data.open_count) + " open") if data else ""}</Text>
        </View>
        {(<Text style={styles.empty}>Loading…</Text>) if not data else (
            (<Text style={styles.hint}>Nothing coming up. Enjoy the room to think.</Text>) if len(data.items) == 0 else (
                <View>
                    {[
                        <View key={it.id} style={[styles.row, {"alignItems": "flex-start", "paddingVertical": S.sm + S.xxs,
                                                               "borderTopWidth": 1, "borderTopColor": C.border}]}>
                            <CheckCircle testID={"cu-done-" + it.id} checked={False} label={"Mark done: " + it.title}
                                onToggle={lambda { onDone(it.id); }}/>
                            <Pressable style={{"flex": 1, "gap": S.xxs}} onPress={lambda { onOpen(it.id); }}>
                                <Text numberOfLines={1} style={{"color": C.text, "fontSize": F.sm + 1, "fontWeight": "600"}}>{it.title}</Text>
                                <Text style={{"color": C.danger if it.overdue else C.muted, "fontSize": F.xs}}>
                                    {("Overdue · " if it.overdue else "Due ") + it.due_day + ((" · " + it.course) if it.course else "")}
                                </Text>
                            </Pressable>
                            <Chip label={it.date_chip} tone={"danger" if it.overdue else "accent"}/>
                        </View>
                        for it in data.items
                    ]}
                </View>
            )
        )}
        {(
            <View style={{"gap": S.sm, "paddingTop": S.md, "borderTopWidth": 1, "borderTopColor": C.border}}>
                <View style={styles.row}>
                    <Text style={[styles.hint, {"flex": 1, "fontSize": F.xs}]}>Weekly follow-through</Text>
                    <Text style={{"color": C.text, "fontSize": F.xs, "fontWeight": "600"}}>{str(data.week_done)}/{str(data.week_total)}</Text>
                </View>
                <View style={{"height": 3, "borderRadius": R.pill, "backgroundColor": C.sunken, "overflow": "hidden"}}>
                    <View style={{"height": 3, "width": str(pct) + "%", "backgroundColor": C.accent}}/>
                </View>
            </View>
        ) if data else <View/>}
    </Card>
}
