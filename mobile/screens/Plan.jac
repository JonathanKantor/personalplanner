"""Plan: the phone version of the web Planner.

A week strip (tap a day, ‹ › for weeks), that day's classes, events and
planned / suggested work, what's due, Suggest / Accept all / Clear, what
couldn't be scheduled, and the "Coming up" card. Tap an item to edit it
(task sheet or event sheet); + Task / + Event add new ones.

Every server call is a walker spawn (core/mobile_api.jac), e.g.
`root spawn WeekScreen(start=...)`; results come back in `.reports`.
"""

import from "@jac/mobui" { View, Text, ScrollView, Pressable }
import from core.mobile_api {
    WeekScreen, ComingUpData, PlanAhead, AcceptAllBlocks, ClearSuggestions,
    DecideBlock, FinishTask, ReopenTask, TaskList
}
import type from core.models { WeekView, DayView, DayItem, ComingUpView, UnscheduledView }
import from ..theme { C, S, R, F, kind_colors, styles }
import from ..lib { today_str, error_text, monday_of }
import from ..components.kit { Button, Card, PageHeader }
import from ..components.EventRow { EventRow }
import from ..components.WeekStrip { WeekStrip }
import from ..components.ComingUpCard { ComingUpCard }
import from ..components.TaskSheet { TaskSheet }
import from ..components.EventSheet { EventSheet }

def:pub PlanScreen() -> JsxElement {
    has start: str = monday_of(today_str()),
        selected: str = today_str(),
        week: WeekView | None = None,
        coming: ComingUpView | None = None,
        unscheduled: list[UnscheduledView] = [],   # from the last Suggest; kept current
        error: str = "",
        notice: str = "",
        busy: bool = False,
        # sheets: task (id, or "" + adding), block it was opened from, event
        task_id: str = "",
        adding_task: bool = False,
        sheet_block: DayItem | None = None,
        sheet_date: str = "",
        event_open: bool = False,
        event_item: DayItem | None = None;

    async def load {
        try {
            week = (root spawn WeekScreen(start=start)).reports[0];
            coming = (root spawn ComingUpData(start=start, limit=5)).reports[0];
            if not any(d.date == selected for d in week.days) {
                selected = today_str() if any(d.is_today for d in week.days) else week.start;
            }
            if len(unscheduled) > 0 {
                open = {t.id: t.status for t in (root spawn TaskList(show_all=False)).reports[0]};
                unscheduled = [u for u in unscheduled if open.get(u.task_id, "done") == "todo"];
            }
        } except Exception as e {
            error = error_text(e);
        }
    }

    # Runs on mount and whenever the week changes.
    async can with [start] entry {
        await load();
    }

    # Each action: clear the old messages, call the server, show any error,
    # then reload so the screen reflects the change.
    def begin {
        error = "";
        notice = "";
        busy = True;
    }

    async def finish {
        busy = False;
        await load();
    }

    async def suggest {
        begin();
        try {
            p = (root spawn PlanAhead(days=21)).reports[0];
            unscheduled = p.unscheduled;
            notice = str(len(p.suggestions)) + " suggestion(s) over the next 3 weeks.";
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    async def accept_all {
        begin();
        try {
            root spawn AcceptAllBlocks();
            unscheduled = [];
            notice = "All suggestions planned.";
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    async def clear {
        begin();
        try {
            n = (root spawn ClearSuggestions()).reports[0];
            unscheduled = [];
            notice = "Cleared " + str(n) + " suggestion(s). Planned blocks stay.";
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    async def decide(id: str, accept: bool) {
        begin();
        try {
            root spawn DecideBlock(block_id=id, accept=accept);
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    """Round checkbox: finish the task, or reopen it."""
    async def toggle_done(task: str, done: bool) {
        begin();
        try {
            if done {
                root spawn ReopenTask(task_id=task);
            } else {
                root spawn FinishTask(task_id=task);
            }
        } except Exception as e {
            error = error_text(e);
        }
        await finish();
    }

    def go_week(step: int) {
        if week {
            start = week.prev_start if step < 0 else week.next_start;
        }
    }

    def open_item(it: DayItem) {
        if it.kind == "block" {
            task_id = it.task_id;
            sheet_block = it;
            sheet_date = selected;
        } elif it.kind == "deadline" {
            task_id = it.task_id;
            sheet_block = None;
        } elif it.editable {
            event_item = it;
            event_open = True;
        }
    }

    def changed(msg: str) {
        notice = msg;
        load();
    }

    day: DayView | None = None;
    if week {
        for d in week.days {
            if d.date == selected { day = d; }
        }
    }
    timed = [it for it in day.items if not it.all_day and it.kind != "deadline"] if day else [];
    due = [it for it in day.items if it.kind == "deadline"] if day else [];
    all_day = [it for it in day.items if it.all_day] if day else [];
    tz = week.timezone if week else "America/Detroit";

    <View style={styles.screen}>
        <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
            <PageHeader eyebrow="Your week, in rhythm" title="A little more room to think."/>

            {(<Text style={styles.error}>{error}</Text>) if error else <View/>}
            {(<Text style={styles.notice}>{notice}</Text>) if notice else <View/>}

            <Card>
                {(<Text style={styles.empty}>Loading…</Text>) if not week else (
                    <WeekStrip week={week} selected={selected} onSelect={lambda (d: str) { selected = d; }}
                        onPrev={lambda { go_week(-1); }} onNext={lambda { go_week(1); }}/>
                )}
                <View style={styles.wrap}>
                    <Button label="Today" small={True} onPress={lambda { start = monday_of(today_str()); selected = today_str(); }}/>
                    <View style={styles.spacer}/>
                    {(<Button label={"Accept all (" + str(week.suggested_count) + ")"} small={True} testID="plan-accept-all"
                        onPress={accept_all} disabled={busy}/>) if week and week.suggested_count > 0 else <View/>}
                    {(<Button label="Clear" variant="ghost" small={True} testID="plan-clear"
                        onPress={clear} disabled={busy}/>) if week and week.suggested_count > 0 else <View/>}
                    <Button label="Suggest" icon="sparkles" small={True} variant="primary" testID="suggest"
                        onPress={suggest} disabled={busy}/>
                </View>
            </Card>

            {(
                <View style={styles.wrap}>
                    {[<View key={it.id} style={{"backgroundColor": C.sunken, "borderRadius": R.pill, "paddingVertical": S.xxs, "paddingHorizontal": S.sm}}>
                        <Text style={{"color": C.muted, "fontSize": F.xs}}>{it.title}</Text></View> for it in all_day]}
                </View>
            ) if len(all_day) > 0 else <View/>}

            <Text style={styles.section}>{(day.label.upper() if day else "SCHEDULE")}</Text>
            {(<Text style={styles.empty}>Nothing scheduled. Tap Suggest to fit your tasks in.</Text>) if week and len(timed) == 0 else (
                <View style={{"gap": S.sm}}>
                    {[<EventRow key={it.id} item={it} onOpen={open_item}
                        onToggleDone={lambda (tid: str, d: bool) { toggle_done(tid, d); }}
                        onAccept={lambda (id: str) { decide(id, True); }}
                        onReject={lambda (id: str) { decide(id, False); }}/>
                      for it in timed]}
                </View>
            )}

            {(
                <View style={{"gap": S.sm}}>
                    <Text style={styles.section}>DUE</Text>
                    {[<EventRow key={it.id} item={it} onOpen={open_item}
                        onToggleDone={lambda (tid: str, d: bool) { toggle_done(tid, d); }}
                        onAccept={lambda (id: str) {}} onReject={lambda (id: str) {}}/>
                      for it in due]}
                </View>
            ) if len(due) > 0 else <View/>}

            <View style={styles.row}>
                <Button label="Task" icon="plus" onPress={lambda { adding_task = True; }} testID="add-task"/>
                <Button label="Event" icon="plus" variant="primary" testID="add-event"
                    onPress={lambda { event_item = None; event_open = True; }}/>
            </View>

            {(
                <Card style={{"borderColor": kind_colors("deadline").border}}>
                    <Text style={styles.cardTitle}>Couldn't fully schedule</Text>
                    {[<Text key={u.task_id} style={{"color": C.danger, "fontSize": F.sm}}>{u.title}: {u.reason}</Text> for u in unscheduled]}
                </Card>
            ) if len(unscheduled) > 0 else <View/>}

            <ComingUpCard data={coming}
                onDone={lambda (id: str) { toggle_done(id, False); }}
                onOpen={lambda (id: str) { task_id = id; sheet_block = None; }}/>
        </ScrollView>

        {(<TaskSheet taskId={task_id} tz={tz} block={sheet_block} blockDate={sheet_date}
            onClose={lambda { task_id = ""; sheet_block = None; }} onChanged={changed}/>) if task_id else <View/>}
        {(<TaskSheet taskId="" tz={tz} defaultDay={selected}
            onClose={lambda { adding_task = False; }} onChanged={changed}/>) if adding_task else <View/>}
        {(<EventSheet day={selected} item={event_item}
            onClose={lambda { event_open = False; }} onChanged={changed}/>) if event_open else <View/>}
    </View>
}
