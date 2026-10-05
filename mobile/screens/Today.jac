"""Today: classes and planned blocks for one day, tasks due that day,
accept/reject suggestions, check off tasks, and quick-add.

Every server call is a walker spawn (`root spawn DayScreen(...)`): the mobile
app is a separate app, and walkers are what it may call on the server
(see core/mobile_api.jac). Results come back in `result.reports`.
"""

import from "@jac/mobui" { View, Text, TextInput, ScrollView, Pressable }
import from "@jac/runtime" { BridgeError }
import from core.mobile_api { DayScreen, FinishTask, DecideBlock, QuickAdd, PlanAhead, LoadDemo }
import type from core.models { DayView, TaskView }
import from ..theme { C, S, R, F, styles }
import from ..lib { today_str, add_days, weekday, error_text }
import from ..components.Button { Button }
import from ..components.Icon { Icon }
import from ..components.ItemRow { ItemRow }

glob EST_CHOICES: list[int] = [30, 60, 90, 120];

def:pub TodayScreen(onLogout: Callable[[], None]) -> JsxElement {
    has day: str = today_str(),
        view: DayView | None = None,
        error: str = "",
        notice: str = "",
        busy: bool = False,
        # quick-add
        title: str = "",
        due_offset: int = 0,                 # days from today
        est: int = 60;

    async def load {
        try {
            result = root spawn DayScreen(day=day);
            view = result.reports[0];
        } except BridgeError as e {
            error = error_text(e);
        } except Exception as e {
            error = error_text(e);
        }
    }

    # Runs on mount and whenever `day` changes.
    async can with [day] entry {
        await load();
    }

    def begin {
        error = "";
        notice = "";
        busy = True;
    }

    async def finish {
        busy = False;
        await load();
    }

    async def decide(id: str, accept: bool) {
        begin();
        try {
            result = root spawn DecideBlock(block_id=id, accept=accept);
            if len(result.reports) == 0 {
                error = "That suggestion no longer exists; refreshing.";
            }
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    async def finish_task(id: str) {
        begin();
        try {
            result = root spawn FinishTask(task_id=id);
            if len(result.reports) > 0 {
                notice = "Done: " + result.reports[0].title;
            }
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    async def plan {
        begin();
        try {
            result = root spawn PlanAhead(days=7);
            p = result.reports[0];
            notice = str(len(p.suggestions)) + " suggestion(s) for the next 7 days.";
            if len(p.unscheduled) > 0 {
                error = "Couldn't fit: " + ", ".join([u.title for u in p.unscheduled]);
            }
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    async def quick_add {
        if not title.strip() {
            return;
        }
        begin();
        try {
            due = add_days(today_str(), due_offset);
            result = root spawn QuickAdd(title=title.strip(), due=due, estimated_minutes=est);
            notice = "Added: " + result.reports[0].title + ". Tap Plan to schedule it.";
            title = "";
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    async def load_demo {
        begin();
        try {
            root spawn LoadDemo();
            notice = "Demo classes and tasks loaded. Tap Plan.";
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    def chip(label: str, on: bool, press: Callable[[], None]) -> JsxElement {
        return <Pressable key={label} style={[styles.chip, styles.chipOn if on else {}]} onPress={press}>
            <Text style={styles.chipTextOn if on else styles.chipText}>{label}</Text>
        </Pressable>;
    }

    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
        {#* header: day + navigation *#}
        <View style={[styles.header, styles.row, {"justifyContent": "space-between"}]}>
            <View>
                <Text style={styles.title}>{"Today" if day == today_str() else (view.label if view else day)}</Text>
                <Text style={styles.subtitle}>{view.label if view and day == today_str() else ""}</Text>
            </View>
            <Pressable testID="logout" onPress={onLogout}><Icon name="logout" size={F.lg} color={C.muted}/></Pressable>
        </View>
        <View style={styles.row}>
            <Pressable testID="prev-day" style={styles.chip} onPress={lambda { day = add_days(day, -1); }}><Icon name="left" size={F.md} color={C.text}/></Pressable>
            {chip("Today", day == today_str(), lambda { day = today_str(); })}
            <Pressable testID="next-day" style={styles.chip} onPress={lambda { day = add_days(day, 1); }}><Icon name="right" size={F.md} color={C.text}/></Pressable>
            <View style={{"flex": 1}}/>
            <Button label="Plan" onPress={plan} disabled={busy}/>
        </View>

        {(<Text style={styles.error}>{error}</Text>) if error else <View/>}
        {(<Text style={styles.notice}>{notice}</Text>) if notice else <View/>}

        {#* all-day events *#}
        {(
            <View style={[styles.row, {"flexWrap": "wrap"}]}>
                {[<View key={it.id} style={[styles.chip, {"backgroundColor": C.eventBg}]}><Text style={styles.chipText}>{it.title}</Text></View>
                  for it in view.items if it.all_day]}
            </View>
        ) if view and any(it.all_day for it in view.items) else <View/>}

        <Text style={styles.section}>SCHEDULE</Text>
        {(
            <View style={{"gap": S.sm}}>
                {[<ItemRow key={it.id} item={it}
                    onAccept={lambda (id: str) { decide(id, True); }}
                    onReject={lambda (id: str) { decide(id, False); }}
                    onFinish={lambda (id: str) { finish_task(id); }}/>
                  for it in view.items if not it.all_day and it.kind != "deadline"]}
            </View>
        ) if view and any(not it.all_day and it.kind != "deadline" for it in view.items) else (
            <View style={{"gap": S.sm}}>
                <Text style={styles.empty}>{"Loading..." if not view else "Nothing scheduled. Tap Plan to fit your tasks in."}</Text>
                {(<Button label="Load demo data" variant="secondary" onPress={load_demo}/>) if view else <View/>}
            </View>
        )}

        <Text style={styles.section}>DUE</Text>
        {(
            <View style={{"gap": S.sm}}>
                {[
                    <Pressable key={t.id} testID={"due-" + t.id} style={[styles.card, {"backgroundColor": C.surface, "borderWidth": 1, "borderColor": C.border}]}
                        onPress={lambda { finish_task(t.id); }} disabled={t.status == "done"}>
                        <Icon name={"check" if t.status == "done" else "circle"} size={F.lg} color={C.planFg if t.status == "done" else C.muted}/>
                        <Text style={[styles.cardTitle, {"color": C.muted if t.status == "done" else C.text, "textDecorationLine": "line-through" if t.status == "done" else "none"}]}>{t.title}</Text>
                        <Text style={[styles.cardSub, {"color": C.muted}]}>{str(t.estimated_minutes)} min</Text>
                    </Pressable>
                    for t in view.due
                ]}
            </View>
        ) if view and len(view.due) > 0 else <Text style={styles.empty}>Nothing due.</Text>}

        {#* quick add *#}
        <View style={[styles.panel, {"marginTop": S.md}]}>
            <Text style={styles.section}>QUICK ADD</Text>
            <View style={styles.row}>
                <TextInput testID="quick-title" style={styles.input} value={title} placeholder="New task"
                    placeholderTextColor={C.muted} onChangeText={lambda (t: str) { title = t; }} onSubmitEditing={quick_add}/>
            </View>
            <View style={[styles.row, {"flexWrap": "wrap"}]}>
                <Text style={styles.subtitle}>Due</Text>
                {[chip("Today" if n == 0 else ("Tomorrow" if n == 1 else weekday(add_days(today_str(), n))), due_offset == n, lambda { due_offset = n; })
                  for n in [0, 1, 2, 3, 4, 5, 6]]}
            </View>
            <View style={[styles.row, {"flexWrap": "wrap"}]}>
                <Text style={styles.subtitle}>Takes</Text>
                {[chip(str(m) + " min", est == m, lambda { est = m; }) for m in EST_CHOICES]}
            </View>
            <Button label="Add task" onPress={quick_add} disabled={busy or not title.strip()}/>
        </View>
    </ScrollView>
}
