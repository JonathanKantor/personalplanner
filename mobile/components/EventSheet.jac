"""Event sheet: add one of your own events (meetings that aren't in Google
Calendar), or edit / delete one by tapping it. The planner schedules
around them."""

import from "@jac/mobui" { View, Text, Switch }
import from core.mobile_api { SaveEvent, RemoveEvent }
import type from core.models { DayItem }
import from ..theme { C, S, F, styles }
import from ..lib { error_text, valid_hhmm, hhmm }
import from .kit { Sheet, Field, Button, Segmented, Choice }
import from .DayPicker { DayPicker }

def:pub EventSheet(
    day: str,
    onClose: Callable[[], None],
    onChanged: Callable[[str], None],
    item: DayItem | None = None
) -> JsxElement {
    has title: str = item.title if item else "",
        date: str = day,
        start: str = hhmm(item.start_min) if item else "15:00",
        end: str = hhmm(item.end_min) if item else "16:00",
        repeat: str = "once",
        weeks: str = "10",
        is_class: bool = False,
        error: str = "",
        busy: bool = False;

    async def save {
        error = "";
        if not (valid_hhmm(start) and valid_hhmm(end)) {
            error = "Times must be HH:MM, e.g. 15:30";
            return;
        }
        busy = True;
        try {
            r = (root spawn SaveEvent(event_id=item.id if item else "", title=title.strip(), day=date,
                    start=start.strip(), end=end.strip(), weeks=int(weeks or "1") if repeat == "weekly" else 1,
                    is_class=is_class)).reports[0];
            msg = ("Saved " if item else "Added ") + title.strip() + "." + (
                (" It overlaps your planned " + ", ".join(r.conflicts) + ".") if len(r.conflicts) > 0 else "");
            busy = False;
            onChanged(msg);
            onClose();
        } except Exception as e {
            busy = False;
            error = error_text(e);
        }
    }

    async def remove(all_repeats: bool) {
        if not item {
            return;
        }
        busy = True;
        try {
            root spawn RemoveEvent(event_id=item.id, whole_series=all_repeats);
            busy = False;
            onChanged("Deleted " + title + ".");
            onClose();
        } except Exception as e {
            busy = False;
            error = error_text(e);
        }
    }

    <Sheet title={"Edit event" if item else "Add event"} onClose={onClose}
        subtitle="Meetings and other commitments that aren't in Google Calendar. The planner schedules around them.">
        {(<Text style={styles.error}>{error}</Text>) if error else <View/>}
        <Field label="Title" value={title} onChange={lambda (t: str) { title = t; }} placeholder="e.g. Advisor meeting" testID="event-title"/>
        <Text style={styles.label}>Date</Text>
        <DayPicker value={date} onChange={lambda (d: str) { date = d; }} testID="event-day"/>
        <View style={styles.row}>
            <Field label="From (24h)" value={start} onChange={lambda (t: str) { start = t; }} testID="event-start" grow={True}/>
            <Field label="To" value={end} onChange={lambda (t: str) { end = t; }} testID="event-end" grow={True}/>
        </View>
        {(
            <View style={{"gap": S.md}}>
                <View style={styles.row}>
                    <Segmented value={repeat} onChange={lambda (v: str) { repeat = v; }}
                        options={[Choice(value="once", label="Once"), Choice(value="weekly", label="Weekly")]}/>
                    {(<Field label="for weeks" value={weeks} onChange={lambda (t: str) { weeks = t; }} numeric={True}/>) if repeat == "weekly" else <View/>}
                </View>
                <View style={styles.row}>
                    <Switch value={is_class} onValueChange={lambda (v: bool) { is_class = v; }}
                        trackColor={{"true": C.accent, "false": C.borderStrong}}/>
                    <Text style={styles.label}>Counts as a class</Text>
                </View>
            </View>
        ) if not item else <View/>}
        <View style={[styles.wrap, {"marginTop": S.sm}]}>
            <Button label={"Save" if item else "Add event"} variant="primary" onPress={save}
                disabled={busy or not title.strip()} testID="event-save"/>
            <View style={styles.spacer}/>
            {(<Button label="Delete" variant="danger" small={True} onPress={lambda { remove(False); }} disabled={busy}/>) if item else <View/>}
            {(<Button label="Delete all repeats" variant="danger" small={True} onPress={lambda { remove(True); }} disabled={busy}/>) if item else <View/>}
        </View>
    </Sheet>
}
