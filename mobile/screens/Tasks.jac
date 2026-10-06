"""Tasks: every task, soonest due first, like the web Tasks page.

Round checkbox: finish a task (or reopen a finished one). Tap a task to edit
or delete it; "Add task" creates one. Both use the task sheet.
"""

import from "@jac/mobui" { View, Text, ScrollView, Pressable }
import from core.mobile_api { TaskList, FinishTask, ReopenTask, Prefs }
import type from core.models { TaskView }
import from ..theme { C, S, F, styles }
import from ..lib { error_text, local_parts, weekday, month_day, clock_ampm }
import from ..components.kit { Button, Card, Chip, CheckCircle, Segmented, Choice, PageHeader }
import from ..components.TaskSheet { TaskSheet }

def:pub TasksScreen() -> JsxElement {
    has tasks: list[TaskView] = [],
        loaded: bool = False,
        show: str = "open",                  # "open" | "all"
        tz: str = "",
        error: str = "",
        notice: str = "",
        open_task: str = "",
        adding: bool = False;

    async def load {
        try {
            if not tz {
                tz = (root spawn Prefs()).reports[0].timezone;
            }
            tasks = (root spawn TaskList(show_all=show == "all")).reports[0];
            loaded = True;
        } except Exception as e {
            error = error_text(e);
        }
    }

    async can with [show] entry {
        await load();
    }

    async def toggle(t: TaskView) {
        error = "";
        try {
            if t.status == "done" {
                root spawn ReopenTask(task_id=t.id);
            } else {
                root spawn FinishTask(task_id=t.id);
            }
        } except Exception as e {
            error = error_text(e);
        }
        await load();
    }

    """"Due Wed, Oct 7 · 11:59pm"."""
    def due_label(iso: str) -> str {
        parts = local_parts(iso, tz or "America/Detroit");
        (h, m) = [int(x) for x in parts[1].split(":")];
        return "Due " + weekday(parts[0]) + ", " + month_day(parts[0]) + " · " + clock_ampm(h * 60 + m);
    }

    open_count = len([t for t in tasks if t.status != "done"]);

    <View style={styles.screen}>
        <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
            <PageHeader eyebrow="Everything on your list" title="Tasks"
                subtitle="Soonest due first. Tap a task to edit it."/>
            {(<Text style={styles.error}>{error}</Text>) if error else <View/>}
            {(<Text style={styles.notice}>{notice}</Text>) if notice else <View/>}

            <View style={styles.row}>
                <Segmented value={show} onChange={lambda (v: str) { show = v; }}
                    options={[Choice(value="open", label="Open"), Choice(value="all", label="All")]}/>
                <View style={styles.spacer}/>
                <Button label="Add task" icon="plus" variant="primary" onPress={lambda { adding = True; }} testID="tasks-add"/>
            </View>

            <Card>
                <Text style={styles.cardTitle}>{str(open_count) + " open"}</Text>
                {(<Text style={styles.empty}>Loading…</Text>) if not loaded else (
                    (<Text style={styles.empty}>{"Nothing on your list. Add one, import from Canvas in Settings, or ask Morrow." if show == "open" else "No tasks yet."}</Text>)
                    if len(tasks) == 0 else (
                        <View>
                            {[
                                <View key={t.id} style={[styles.row, {"alignItems": "flex-start", "paddingVertical": S.md,
                                                                      "borderTopWidth": 1, "borderTopColor": C.border}]}>
                                    <CheckCircle testID={"task-check-" + t.id} checked={t.status == "done"}
                                        label={("Reopen: " if t.status == "done" else "Mark done: ") + t.title}
                                        onToggle={lambda { toggle(t); }}/>
                                    <Pressable testID={"task-" + t.id} style={{"flex": 1, "gap": S.xs}} onPress={lambda { open_task = t.id; }}>
                                        <Text style={{"color": C.muted if t.status == "done" else C.text, "fontSize": F.md, "fontWeight": "600",
                                                      "textDecorationLine": "line-through" if t.status == "done" else "none"}}>{t.title}</Text>
                                        <Text style={{"color": C.muted, "fontSize": F.xs}}>{due_label(t.due)} · {str(t.estimated_minutes)} min</Text>
                                        <View style={styles.wrap}>
                                            {(<Chip label={t.category}/>) if t.category else <View/>}
                                            {(<Chip label="High" tone="danger"/>) if t.priority == "high" and t.status != "done" else <View/>}
                                            {(<Chip label="Planned" tone="accent"/>) if t.status == "scheduled" else <View/>}
                                            {(<Chip label="Repeats"/>) if t.recurrence else <View/>}
                                        </View>
                                    </Pressable>
                                </View>
                                for t in tasks
                            ]}
                        </View>
                    )
                )}
            </Card>
        </ScrollView>

        {(<TaskSheet taskId={open_task} tz={tz} onClose={lambda { open_task = ""; }}
            onChanged={lambda (msg: str) { notice = msg; load(); }}/>) if open_task else <View/>}
        {(<TaskSheet taskId="" tz={tz} onClose={lambda { adding = False; }}
            onChanged={lambda (msg: str) { notice = msg; load(); }}/>) if adding else <View/>}
    </View>
}
