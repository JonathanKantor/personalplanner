"""web - Entry point of the server and the web client.

This app owns the backend: every endpoint is imported by name below, which is
what registers it at POST /function/<name>. (Jac only reliably registers
endpoints that the entry module names explicitly.) The mobile app and CLI call
these same endpoints over HTTP.
"""

import from core.tasks {
    create_task, list_tasks, get_task, update_task, complete_task, delete_task
}
import from core.preferences { get_preferences, update_preferences }
import from core.calendars {
    import_ics, import_ics_url, list_calendars, set_calendar_is_class,
    list_series, set_series_is_class, list_events, delete_calendar
}
import from core.sync { sync_calendar }
import from core.gcal {
    google_status, google_auth_url, connect_google, disconnect_google
}
import from core.planning {
    suggest_schedule, list_blocks, accept_block, reject_block, accept_all, clear_suggestions,
    adjust_block, get_agenda, get_today, get_progress
}
import from core.views { get_week_view, get_day_view }
import from core.canvas { canvas_sync, canvas_import, canvas_feed_url, canvas_forget }
import from core.assistant { assistant_chat, assistant_history, assistant_reset, assistant_status }
import from core.events { create_event, update_event, delete_event }
import from core.seed { seed_demo_data }

# ---------------------------------------------------------------- client
# Everything below is browser code: JSX and the CSS import mark it "client".
# Pages live in web/pages/ (file-based routing: the file path is the URL).
# `app` wraps every page; `children` is the page the router picked.

import ".styles.global.css";

def:pub app(children: any) -> JsxElement {
    <>{children}</>
}
