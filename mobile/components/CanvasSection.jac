"""Settings section: import Canvas assignments as tasks from the Canvas
calendar feed (same as the web Settings section).

1. Paste the feed link (Canvas: Calendar -> "Calendar Feed") and Load.
2. Tick the assignments to import and set each one's estimate.
3. Import. Later, Sync refreshes due dates and shows only new assignments.
"""

import from "@jac/mobui" { View, Text, Switch }
import from core.mobile_api { CanvasFeed, CanvasLoad, CanvasImport, Prefs }
import type from core.models { CanvasPreview }
import from ..theme { C, S, F, styles }
import from ..lib { error_text, local_parts, weekday, month_day }
import from .kit { Card, Button, Field, Chip }

glob QUICK_MINUTES: list[int] = [30, 60, 120, 180];

"""One assignment row (client-side state)."""
obj Row {
    has uid: str, title: str, course: str, due: str, status: str, picked: bool, minutes: int;
}

def:pub CanvasSection() -> JsxElement {
    has url: str = "",
        rows: list[Row] = [],
        loaded: bool = False,
        tz: str = "America/Detroit",
        error: str = "",
        notice: str = "",
        busy: bool = False;

    async can with entry {
        try {
            url = (root spawn CanvasFeed()).reports[0];
            tz = (root spawn Prefs()).reports[0].timezone;
        } except Exception as e {
            error = error_text(e);
        }
    }

    def to_rows(p: CanvasPreview) -> list[Row] {
        return [Row(uid=i.uid, title=i.title, course=i.course, due=i.due, status=i.status,
                    picked=i.status == "new", minutes=60) for i in p.items];
    }

    async def load {
        error = "";
        notice = "";
        busy = True;
        try {
            p = (root spawn CanvasLoad(url=url.strip())).reports[0];
            url = p.feed_url;
            rows = to_rows(p);
            loaded = True;
            notice = str(len([r for r in rows if r.status == "new"])) + " new assignment(s).";
        } except Exception as e {
            error = error_text(e);
        }
        busy = False;
    }

    """Rows are replaced, not edited in place, so the screen re-renders."""
    def set_row(uid: str, picked: bool, minutes: int) {
        rows = [Row(uid=r.uid, title=r.title, course=r.course, due=r.due, status=r.status,
                    picked=picked if r.uid == uid else r.picked, minutes=minutes if r.uid == uid else r.minutes)
                for r in rows];
    }

    async def do_import {
        error = "";
        busy = True;
        try {
            choices = [{"uid": r.uid, "include": r.picked, "title": r.title, "course": r.course,
                        "estimated_minutes": r.minutes, "priority": "medium"} for r in rows if r.status != "imported"];
            res = (root spawn CanvasImport(choices=choices)).reports[0];
            notice = "Imported " + str(res.created) + " task(s). Open Plan and tap Suggest.";
            rows = to_rows((root spawn CanvasLoad(url="")).reports[0]);
        } except Exception as e {
            error = error_text(e);
        }
        busy = False;
    }

    def due_text(iso: str) -> str {
        p = local_parts(iso, tz);
        return "Due " + weekday(p[0]) + ", " + month_day(p[0]);
    }

    chosen = len([r for r in rows if r.picked and r.status != "imported"]);

    <Card>
        <Text style={styles.cardTitle}>Canvas assignments</Text>
        <Text style={styles.hint}>In Canvas, open Calendar and tap "Calendar Feed". Copy the link and paste it here. It's private to you, like a password.</Text>
        <Field label="Feed link" value={url} onChange={lambda (t: str) { url = t; }} testID="feed-url"
            placeholder="https://umich.instructure.com/feeds/calendars/user_….ics"/>
        <Button label={"Sync" if loaded else "Load assignments"} variant="primary" onPress={load} disabled={busy or not url.strip()} testID="canvas-load"/>
        {(<Text style={styles.error}>{error}</Text>) if error else <View/>}
        {(<Text style={styles.notice}>{notice}</Text>) if notice else <View/>}
        {(
            <View>
                {[
                    <View key={r.uid} style={{"gap": S.sm, "paddingVertical": S.md, "borderTopWidth": 1, "borderTopColor": C.border,
                                              "opacity": 0.55 if r.status == "imported" else 1.0}}>
                        <View style={styles.row}>
                            <Switch value={r.picked} disabled={r.status == "imported"}
                                onValueChange={lambda (v: bool) { set_row(r.uid, v, r.minutes); }}
                                trackColor={{"true": C.accent, "false": C.borderStrong}}/>
                            <View style={{"flex": 1, "gap": S.xxs}}>
                                <Text style={{"color": C.text, "fontWeight": "600", "fontSize": F.sm + 1}}>{r.title}</Text>
                                <Text style={{"color": C.muted, "fontSize": F.xs}}>{due_text(r.due)}{(" · " + r.course) if r.course else ""}</Text>
                            </View>
                            {(<Chip label={"imported" if r.status == "imported" else ("skipped before" if r.status == "dismissed" else "past due")}
                                tone={"accent" if r.status == "imported" else "neutral"}/>) if r.status != "new" else <View/>}
                        </View>
                        {(
                            <View style={styles.wrap}>
                                {[<Button key={str(m)} label={str(m) + " min"} small={True} variant={"primary" if r.minutes == m else "outline"}
                                    onPress={lambda { set_row(r.uid, r.picked, m); }}/> for m in QUICK_MINUTES]}
                            </View>
                        ) if r.status != "imported" and r.picked else <View/>}
                    </View>
                    for r in rows
                ]}
                <Button label={"Import " + str(chosen) + " task(s)"} variant="primary" onPress={do_import}
                    disabled={busy or chosen == 0} testID="canvas-import"/>
                <Text style={[styles.hint, {"marginTop": S.sm}]}>Unticked assignments are remembered as skipped. Due dates always come from Canvas.</Text>
            </View>
        ) if loaded else <View/>}
    </Card>
}
