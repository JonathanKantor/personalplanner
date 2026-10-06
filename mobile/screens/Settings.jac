"""Settings: your name and city, working hours and limits, days off, Canvas
import, demo data, and log out. (Connecting Google Calendar and uploading
.ics files are on the web app's Settings page.)"""

import from "@jac/mobui" { View, Text, ScrollView, Pressable }
import from core.mobile_api { Prefs, SavePrefs, LoadDemo }
import from ..theme { C, S, R, F, styles }
import from ..lib { error_text, valid_hhmm }
import from ..components.kit { Card, Button, Field, PageHeader }
import from ..components.CanvasSection { CanvasSection }

glob DAYS: list[str] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

def:pub SettingsScreen(onLogout: Callable[[], None]) -> JsxElement {
    has name: str = "",
        city: str = "",
        timezone: str = "",
        work_start: str = "",
        work_end: str = "",
        preferred_start: str = "",
        preferred_end: str = "",
        min_break: str = "",
        max_focus: str = "",
        days_off: list[str] = [],
        error: str = "",
        notice: str = "",
        busy: bool = False;

    async can with entry {
        try {
            p = (root spawn Prefs()).reports[0];
            name = p.display_name;
            city = p.city;
            timezone = p.timezone;
            work_start = p.work_start;
            work_end = p.work_end;
            preferred_start = p.preferred_start;
            preferred_end = p.preferred_end;
            min_break = str(p.min_break_minutes);
            max_focus = str(p.max_focus_minutes_per_day);
            days_off = p.days_off;
        } except Exception as e {
            error = error_text(e);
        }
    }

    async def save {
        error = "";
        notice = "";
        times = [work_start, work_end] + [t for t in [preferred_start, preferred_end] if t.strip()];
        if not all(valid_hhmm(t) for t in times) {
            error = "Times must be HH:MM (24h), e.g. 09:00";
            return;
        }
        busy = True;
        try {
            root spawn SavePrefs(changes={
                "display_name": name.strip(), "city": city.strip(), "timezone": timezone.strip(),
                "work_start": work_start.strip(), "work_end": work_end.strip(),
                "preferred_start": preferred_start.strip(), "preferred_end": preferred_end.strip(),
                "min_break_minutes": int(min_break or "0"), "max_focus_minutes_per_day": int(max_focus or "0"),
                "days_off": days_off
            });
            notice = "Saved.";
        } except Exception as e {
            error = error_text(e);
        }
        busy = False;
    }

    async def demo {
        try {
            root spawn LoadDemo();
            notice = "Demo classes and tasks loaded. Open Plan and tap Suggest.";
        } except Exception as e {
            error = error_text(e);
        }
    }

    def toggle_day(d: str) {
        days_off = [x for x in days_off if x != d] if d in days_off else days_off + [d];
    }

    <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
        <PageHeader eyebrow="Settings" title="Make it yours" subtitle="Your hours, your calendars, and how the planner fits work around them."/>
        {(<Text style={styles.error}>{error}</Text>) if error else <View/>}
        {(<Text style={styles.notice}>{notice}</Text>) if notice else <View/>}

        <Card>
            <Text style={styles.cardTitle}>You</Text>
            <View style={styles.row}>
                <Field label="Your name" value={name} onChange={lambda (t: str) { name = t; }} placeholder="Maya Chen" grow={True} testID="pref-name"/>
                <Field label="City" value={city} onChange={lambda (t: str) { city = t; }} placeholder="Ann Arbor" grow={True}/>
            </View>
            <Field label="Timezone" value={timezone} onChange={lambda (t: str) { timezone = t; }}/>
        </Card>

        <Card>
            <Text style={styles.cardTitle}>Hours and limits</Text>
            <View style={styles.row}>
                <Field label="Work from" value={work_start} onChange={lambda (t: str) { work_start = t; }} grow={True}/>
                <Field label="Work until" value={work_end} onChange={lambda (t: str) { work_end = t; }} grow={True}/>
            </View>
            <View style={styles.row}>
                <Field label="Prefer study from" value={preferred_start} onChange={lambda (t: str) { preferred_start = t; }} placeholder="optional" grow={True}/>
                <Field label="until" value={preferred_end} onChange={lambda (t: str) { preferred_end = t; }} placeholder="optional" grow={True}/>
            </View>
            <View style={styles.row}>
                <Field label="Break (min)" value={min_break} onChange={lambda (t: str) { min_break = t; }} numeric={True} grow={True}/>
                <Field label="Max focus / day (min)" value={max_focus} onChange={lambda (t: str) { max_focus = t; }} numeric={True} grow={True}/>
            </View>
            <Text style={styles.label}>Days off</Text>
            <View style={styles.wrap}>
                {[<Pressable key={d} testID={"off-" + d} onPress={lambda { toggle_day(d); }}
                    style={{"paddingVertical": S.xs + S.xxs, "paddingHorizontal": S.md, "borderRadius": R.pill, "borderWidth": 1,
                            "borderColor": C.accent if d in days_off else C.borderStrong,
                            "backgroundColor": C.accentTint if d in days_off else C.surface}}>
                    <Text style={{"fontSize": F.sm, "color": C.accentInk if d in days_off else C.text}}>{d.capitalize()}</Text>
                  </Pressable> for d in DAYS]}
            </View>
            <Button label="Save" variant="primary" onPress={save} disabled={busy} testID="pref-save"/>
        </Card>

        <CanvasSection/>

        <Card>
            <Text style={styles.cardTitle}>Calendars</Text>
            <Text style={styles.hint}>Connect Google Calendar, upload .ics files and mark which events are classes on the web app's Settings page.</Text>
            <Button label="Load demo classes and tasks" onPress={demo}/>
        </Card>

        <Button label="Log out" icon="logout" variant="danger" onPress={onLogout} testID="logout"/>
    </ScrollView>
}
