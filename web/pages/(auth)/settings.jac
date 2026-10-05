"""/settings - preferences, calendar connection and import, class marking."""

import from core.preferences { get_preferences, update_preferences }
import from core.calendars {
    list_calendars, set_calendar_is_class, list_series, set_series_is_class,
    import_ics, import_ics_url, delete_calendar
}
import from core.sync { sync_calendar }
import from core.gcal { google_status, google_auth_url, disconnect_google }
import from core.seed { seed_demo_data }
import type from core.models { CalendarView, SeriesView, SyncResult }
import from ...lib.ui { error_text }
import from ...components.PageHeader { PageHeader }
import from ...components.kit { Chip }

glob DAYS: list[str] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

def:pub SettingsPage() -> JsxPage {
    has error: str = "",
        notice: str = "",
        busy: bool = False,
        # preferences form
        timezone: str = "",
        display_name: str = "",
        city: str = "",
        work_start: str = "",
        work_end: str = "",
        days_off: list[str] = [],
        preferred_start: str = "",
        preferred_end: str = "",
        min_break: str = "",
        max_focus: str = "",
        # calendars
        calendars: list[CalendarView] = [],
        series: list[SeriesView] = [],
        google_configured: bool = False,
        google_connected: bool = False,
        ics_url: str = "",
        ics_name: str = "";

    async def load {
        try {
            p = await get_preferences();
            timezone = p.timezone;
            display_name = p.display_name;
            city = p.city;
            work_start = p.work_start;
            work_end = p.work_end;
            days_off = p.days_off;
            preferred_start = p.preferred_start;
            preferred_end = p.preferred_end;
            min_break = str(p.min_break_minutes);
            max_focus = str(p.max_focus_minutes_per_day);
            calendars = await list_calendars();
            series = await list_series();
            g = await google_status();
            google_configured = g["configured"];
            google_connected = g["connected"];
        } except Exception as e {
            error = error_text(e);
        }
    }

    async can with entry {
        await load();
    }

    def show_sync(results: list[SyncResult]) {
        if len(results) == 0 {
            notice = "Nothing to sync yet: connect Google or add an iCal URL.";
            return;
        }
        notice = "; ".join([
            r.calendar + ": " + str(r.added) + " added, " + str(r.updated) + " updated, " + str(r.removed) + " removed"
            for r in results
        ]);
    }

    async def save_prefs(e: FormEvent) {
        e.preventDefault();
        error = "";
        notice = "";
        try {
            await update_preferences({
                "timezone": timezone, "work_start": work_start, "work_end": work_end,
                "display_name": display_name, "city": city,
                "days_off": days_off, "preferred_start": preferred_start,
                "preferred_end": preferred_end, "min_break_minutes": int(min_break),
                "max_focus_minutes_per_day": int(max_focus)
            });
            notice = "Preferences saved.";
        } except Exception as ex {
            error = error_text(ex);
        }
    }

    def toggle_day(day: str) {
        days_off = [d for d in days_off if d != day] if day in days_off else days_off + [day];
    }

    async def connect_google {
        error = "";
        try {
            url = await google_auth_url();
            window.location.assign(url);           # leave for Google's consent page
        } except Exception as ex {
            error = error_text(ex);
        }
    }

    async def disconnect {
        try {
            await disconnect_google();
            notice = "Google disconnected.";
        } except Exception as ex {
            error = error_text(ex);
        }
        await load();
    }

    async def sync_now {
        error = "";
        busy = True;
        try {
            show_sync(await sync_calendar());
        } except Exception as ex {
            error = error_text(ex);
        }
        busy = False;
        await load();
    }

    async def import_url {
        error = "";
        busy = True;
        try {
            show_sync([await import_ics_url(ics_url, ics_name)]);
            ics_url = "";
        } except Exception as ex {
            error = error_text(ex);
        }
        busy = False;
        await load();
    }

    async def import_file(e: ChangeEvent) {
        error = "";
        file: any = e.target.files[0];             # browser File object (untyped for jac check)
        if not file {
            return;
        }
        busy = True;
        try {
            text: str = await file.text();          # browser File API: read as text
            show_sync([await import_ics(text, ics_name)]);
        } except Exception as ex {
            error = error_text(ex);
        }
        busy = False;
        await load();
    }

    async def set_cal_class(id: str, on: bool) {
        try {
            await set_calendar_is_class(id, on);
        } except Exception as ex {
            error = error_text(ex);
        }
        await load();
    }

    async def set_series_class(id: str, on: bool) {
        try {
            await set_series_is_class(id, on);
        } except Exception as ex {
            error = error_text(ex);
        }
        await load();
    }

    async def remove_calendar(id: str) {
        try {
            await delete_calendar(id);
        } except Exception as ex {
            error = error_text(ex);
        }
        await load();
    }

    async def demo {
        error = "";
        try {
            r = await seed_demo_data();
            notice = "Demo data loaded: " + str(r["tasks_created"]) + " tasks and the demo calendars.";
        } except Exception as ex {
            error = error_text(ex);
        }
        await load();
    }

    <div className="narrow">
        <PageHeader eyebrow="Settings" title="Make it yours"
                    subtitle="Your hours, your calendars, and how the planner fits work around them." />
        {error and <div className="error">{error}</div>}
        {notice and <div className="notice">{notice}</div>}

        <form className="panel" onSubmit={save_prefs}>
            <h2>Preferences</h2>
            <div className="form-grid">
                <label className="field">Your name (shown in the header)
                    <input id="display-name" value={display_name} placeholder="e.g. Maya Chen"
                        onChange={lambda (e: ChangeEvent) { display_name = e.target.value; }} />
                </label>
                <label className="field">City (shown next to today's date)
                    <input id="city" value={city} placeholder="e.g. Ann Arbor"
                        onChange={lambda (e: ChangeEvent) { city = e.target.value; }} />
                </label>
                <label className="field">Timezone
                    <input id="timezone" value={timezone} onChange={lambda (e: ChangeEvent) { timezone = e.target.value; }} />
                </label>
                <label className="field">Work from
                    <input id="work_start" type="time" value={work_start} onChange={lambda (e: ChangeEvent) { work_start = e.target.value; }} />
                </label>
                <label className="field">Work until
                    <input id="work_end" type="time" value={work_end} onChange={lambda (e: ChangeEvent) { work_end = e.target.value; }} />
                </label>
                <label className="field">Preferred study from
                    <input type="time" value={preferred_start} onChange={lambda (e: ChangeEvent) { preferred_start = e.target.value; }} />
                </label>
                <label className="field">Preferred study until
                    <input type="time" value={preferred_end} onChange={lambda (e: ChangeEvent) { preferred_end = e.target.value; }} />
                </label>
                <label className="field">Min break (min)
                    <input type="number" min="0" value={min_break} onChange={lambda (e: ChangeEvent) { min_break = e.target.value; }} />
                </label>
                <label className="field">Max focus per day (min)
                    <input type="number" min="1" max="1440" value={max_focus} onChange={lambda (e: ChangeEvent) { max_focus = e.target.value; }} />
                </label>
            </div>
            <div className="row mt-3">
                <span className="muted">Days off:</span>
                {for d in DAYS {
                    <label key={d} className="row">
                        <input type="checkbox" checked={d in days_off} onChange={lambda (e: ChangeEvent) { toggle_day(d); }} />
                        {d}
                    </label>
                }}
            </div>
            <div className="row mt-4">
                <button id="save-prefs" className="btn primary" type="submit">Save preferences</button>
                <span className="muted">Leave the preferred window empty for no preference.</span>
            </div>
        </form>

        <div className="panel">
            <h2>Google Calendar</h2>
            {if not google_configured {
                <p className="muted">Not configured on the server: set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in .env (see README). You can still import an .ics file or iCal URL below.</p>
            } elif google_connected {
                <div className="row">
                    <span>Connected (read-only).</span>
                    <button className="btn" onClick={sync_now} disabled={busy}>Sync now</button>
                    <button className="btn danger" onClick={disconnect}>Disconnect</button>
                </div>
            } else {
                <div className="row">
                    <button id="connect-google" className="btn primary" onClick={connect_google}>Connect Google Calendar</button>
                    <span className="muted">Read-only access; you'll come back here afterwards.</span>
                </div>
            }}
        </div>

        <div className="panel">
            <h2>Import a calendar (.ics)</h2>
            <div className="form-grid">
                <label className="field">Name (optional)
                    <input value={ics_name} onChange={lambda (e: ChangeEvent) { ics_name = e.target.value; }} />
                </label>
                <label className="field wide">Private iCal URL (https:// or webcal://)
                    <input id="ics-url" value={ics_url} onChange={lambda (e: ChangeEvent) { ics_url = e.target.value; }} />
                </label>
            </div>
            <div className="row mt-3">
                <button className="btn" onClick={import_url} disabled={busy or not ics_url}>Import URL</button>
                <span className="muted">or upload a file:</span>
                <input type="file" aria-label="Upload an .ics file" accept=".ics,text/calendar" onChange={import_file} />
                {if not google_connected {
                    <button className="btn" onClick={sync_now} disabled={busy}>Re-sync URLs</button>
                }}
            </div>
        </div>

        <div className="panel">
            <h2>Calendars</h2>
            {if len(calendars) == 0 {
                <p className="muted">No calendars yet. Connect Google, import one above, or <a href="#" onClick={lambda (e: MouseEvent) { e.preventDefault(); demo(); }}>load demo data</a>.</p>
            }}
            <ul className="list">
                {for c in calendars {
                    <li key={c.id}>
                        <div className="grow"><b>{c.name}</b> <Chip label={c.source} />
                            <div className="reason">{c.event_count} events{(" · synced " + new(Date, c.last_synced).toLocaleString()) if c.last_synced else ""}</div>
                        </div>
                        <label className="row"><input type="checkbox" checked={c.is_class}
                            onChange={lambda (e: ChangeEvent) { set_cal_class(c.id, e.target.checked); }} /> all classes</label>
                        <button className="btn small danger" onClick={lambda (e: MouseEvent) { remove_calendar(c.id); }}>Remove</button>
                    </li>
                }}
            </ul>
            {if len(series) > 0 {
                <h2 className="mt-4">Recurring events</h2>
                <p className="muted">Tick the ones that are classes.</p>
                <ul className="list">
                    {for s in series {
                        <li key={s.series_id}>
                            <label className="row grow"><input type="checkbox" checked={s.is_class}
                                onChange={lambda (e: ChangeEvent) { set_series_class(s.series_id, e.target.checked); }} />
                                <b>{s.title}</b> <span className="muted">{s.occurrences}x · {s.calendar}</span></label>
                        </li>
                    }}
                </ul>
            }}
        </div>

        <div className="panel">
            <h2>Demo</h2>
            <button className="btn" onClick={demo}>Load demo classes and tasks</button>
        </div>
    </div>
}
