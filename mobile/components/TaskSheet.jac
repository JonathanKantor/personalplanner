"""Task sheet. With taskId "" it adds a task; otherwise it edits one (opened
by tapping a task, a deadline or a planned block).

Edits the task (title, due, estimate, priority, course, notes; mark done;
delete). Opened from a block, it also has that block's actions: accept /
reject a suggestion, change its time, or remove it from the calendar.
"""

import from "@jac/mobui" { View, Text }
import from core.mobile_api { TaskDetail, SaveTask, FinishTask, RemoveTask, DecideBlock, MoveBlock }
import type from core.models { TaskView, DayItem }
import from ..theme { C, S, R, F, kind_colors, styles }
import from ..lib { today_str, error_text, local_parts, valid_hhmm, hhmm, time_range }
import from .kit { Sheet, Field, Button, Segmented, Choice }
import from .DayPicker { DayPicker }

glob EST_CHOICES: list[int] = [30, 60, 90, 120, 180];

def _nothing(item: DayItem | None) {}

def:pub TaskSheet(
    taskId: str,
    tz: str,
    onClose: Callable[[], None],
    onChanged: Callable[[str], None],
    block: DayItem | None = None,
    blockDate: str = "",
    defaultDay: str = ""
) -> JsxElement {
    has task: TaskView | None = None,
        ready: bool = False,
        error: str = "",
        busy: bool = False,
        confirm_delete: bool = False,
        title: str = "",
        due_day: str = defaultDay or today_str(),
        due_time: str = "23:59",
        minutes: str = "60",
        priority: str = "medium",
        course: str = "",
        notes: str = "",
        repeat: str = "",
        b_day: str = blockDate,
        b_start: str = hhmm(block.start_min) if block else "",
        b_end: str = hhmm(block.end_min) if block else "";
    creating = not taskId;

    async can with entry {
        if creating {
            ready = True;
            return;
        }
        try {
            t = (root spawn TaskDetail(task_id=taskId)).reports[0];
            task = t;
            title = t.title;
            parts = local_parts(t.due, tz);
            due_day = parts[0];
            due_time = parts[1];
            minutes = str(t.estimated_minutes);
            priority = t.priority;
            course = t.category;
            notes = t.notes;
            ready = True;
        } except Exception as e {
            error = error_text(e);
        }
    }

    """Run one action; on success tell the screen and close."""
    async def act(action: str) {
        error = "";
        if action == "save" and not valid_hhmm(due_time) {
            error = "Due time must be HH:MM, e.g. 17:00";
            return;
        }
        if action == "move" and not (valid_hhmm(b_start) and valid_hhmm(b_end)) {
            error = "Times must be HH:MM, e.g. 15:30";
            return;
        }
        busy = True;
        msg = "";
        try {
            if action == "save" {
                root spawn SaveTask(task_id=taskId, title=title.strip(), due=due_day + "T" + due_time.strip(),
                    priority=priority, estimated_minutes=int(minutes or "0"), category=course.strip(),
                    notes=notes.strip(), recurrence=repeat.strip());
                msg = ("Added " if creating else "Saved ") + title.strip() + ".";
            } elif action == "done" {
                root spawn FinishTask(task_id=taskId);
                msg = "Done: " + title + ".";
            } elif action == "delete" {
                root spawn RemoveTask(task_id=taskId);
                msg = "Deleted " + title + ".";
            } elif action == "accept" and block {
                root spawn DecideBlock(block_id=block.id, accept=True);
                msg = "Planned " + title + ".";
            } elif action == "reject" and block {
                root spawn DecideBlock(block_id=block.id, accept=False);
                msg = ("Rejected that slot." if block.status == "suggested" else "Removed it from the calendar.");
            } elif action == "move" and block {
                root spawn MoveBlock(block_id=block.id, day=b_day, start=b_start.strip(), end=b_end.strip());
                msg = "Moved " + title + " to " + b_start.strip() + ".";
            }
            busy = False;
            onChanged(msg);
            onClose();
        } except Exception as e {
            busy = False;
            error = error_text(e);
        }
    }

    blockColors = kind_colors("focus" if block and block.status == "suggested" else "deadline");

    <Sheet title={"Add task" if creating else "Edit task"} onClose={onClose}>
        {(<Text style={styles.error}>{error}</Text>) if error else <View/>}
        {(<Text style={styles.empty}>{"" if error else "Loading…"}</Text>) if not ready else (
            <View style={{"gap": S.md}}>
                {(
                    <View style={{"gap": S.sm, "padding": S.md, "borderRadius": R.block, "backgroundColor": blockColors.bg,
                                  "borderLeftWidth": 3, "borderLeftColor": blockColors.border}}>
                        <Text style={{"color": blockColors.text, "fontWeight": "600"}}>
                            {("Suggested " if block.status == "suggested" else "Planned ") + time_range(block.start_min, block.end_min)}
                        </Text>
                        {(<Text style={{"color": blockColors.text, "fontSize": F.xs}}>{block.reason}</Text>) if block.reason else <View/>}
                        <DayPicker value={b_day} onChange={lambda (d: str) { b_day = d; }} testID="block-day"/>
                        <View style={styles.row}>
                            <Field label="From" value={b_start} onChange={lambda (t: str) { b_start = t; }} testID="block-start" grow={True}/>
                            <Field label="To" value={b_end} onChange={lambda (t: str) { b_end = t; }} testID="block-end" grow={True}/>
                        </View>
                        <View style={styles.wrap}>
                            <Button label="Change time" small={True} onPress={lambda { act("move"); }} disabled={busy} testID="block-move"/>
                            {(<Button label="Accept" variant="primary" small={True} onPress={lambda { act("accept"); }} disabled={busy} testID="block-accept"/>) if block.status == "suggested" else <View/>}
                            <Button label={"Reject" if block.status == "suggested" else "Remove from calendar"} variant="danger" small={True}
                                onPress={lambda { act("reject"); }} disabled={busy} testID="block-reject"/>
                        </View>
                    </View>
                ) if block else <View/>}

                <Field label="Title" value={title} onChange={lambda (t: str) { title = t; }} placeholder="e.g. Problem set 5" testID="task-title"/>
                <Text style={styles.label}>Due</Text>
                <DayPicker value={due_day} onChange={lambda (d: str) { due_day = d; }} testID="task-due"/>
                <View style={styles.row}>
                    <Field label="Due time (24h)" value={due_time} onChange={lambda (t: str) { due_time = t; }} testID="task-time" grow={True}/>
                    <Field label="Estimate (min)" value={minutes} onChange={lambda (t: str) { minutes = t; }} numeric={True} testID="task-minutes" grow={True}/>
                </View>
                <View style={styles.wrap}>
                    {[<Button key={str(m)} label={str(m) + " min"} small={True} variant={"primary" if minutes == str(m) else "outline"}
                        onPress={lambda { minutes = str(m); }}/> for m in EST_CHOICES]}
                </View>
                <Text style={styles.label}>Priority</Text>
                <Segmented value={priority} onChange={lambda (v: str) { priority = v; }}
                    options={[Choice(value="high", label="High"), Choice(value="medium", label="Medium"), Choice(value="low", label="Low")]}/>
                <View style={styles.row}>
                    <Field label="Course / category" value={course} onChange={lambda (t: str) { course = t; }} placeholder="EECS 449" grow={True}/>
                    {(<Field label="Repeat" value={repeat} onChange={lambda (t: str) { repeat = t; }} placeholder="WEEKLY:MO,WE" grow={True}/>) if creating else <View/>}
                </View>
                <Field label="Notes" value={notes} onChange={lambda (t: str) { notes = t; }}/>

                <View style={[styles.wrap, {"marginTop": S.sm}]}>
                    <Button label={"Add task" if creating else "Save"} variant="primary" testID="task-save"
                        onPress={lambda { act("save"); }} disabled={busy or not title.strip()}/>
                    {(<Button label="Mark done" onPress={lambda { act("done"); }} disabled={busy} testID="task-done"/>) if task and task.status != "done" else <View/>}
                    <View style={styles.spacer}/>
                    {(<View/>) if creating else (
                        (<Button label="Really delete?" variant="danger" onPress={lambda { act("delete"); }} disabled={busy} testID="task-delete-confirm"/>)
                        if confirm_delete else
                        (<Button label="Delete" variant="danger" icon="trash" onPress={lambda { confirm_delete = True; }} testID="task-delete"/>)
                    )}
                </View>
            </View>
        )}
    </Sheet>
}
