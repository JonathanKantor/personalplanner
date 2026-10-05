"""/oauth/callback - where Google sends the browser after the consent screen.

Google appends ?code=...&state=... (or ?error=...). This page hands them to the
server's connect_google endpoint, which swaps the code for a refresh token and
imports your calendars, then links back to Settings.
"""

import from "@jac/runtime" { useLocation, Link }
import from core.gcal { connect_google }
import type from core.models { SyncResult }
import from ....lib.ui { error_text }

def:pub OAuthCallback() -> JsxPage {
    has status: str = "Connecting to Google Calendar...",
        error: str = "",
        results: list[SyncResult] = [];
    location = useLocation();

    async can with entry {
        # Browser API. `jac check` has no type info for browser globals, so the
        # value is typed `any` (it works at runtime; see jac-cl-js-interop).
        params: any = new(URLSearchParams, location.search);  # jac:ignore[E1053]
        code = params.get("code");
        state = params.get("state");
        if params.get("error") {
            error = "Google said: " + params.get("error");
            status = "";
            return;
        }
        if not code or not state {
            error = "This page expects ?code=...&state=... from Google. Start again from Settings.";
            status = "";
            return;
        }
        try {
            results = await connect_google(code, state);
            status = "Connected.";
        } except Exception as e {
            error = error_text(e);
            status = "";
        }
    }

    <div className="panel" style={{"maxWidth": "var(--dialog-width)"}}>
        <h2>Google Calendar</h2>
        {status and <p id="status">{status}</p>}
        {error and <div className="error">{error}</div>}
        {if len(results) > 0 {
            <ul className="list">
                {for r in results {
                    <li key={r.calendar}>{r.calendar}: {r.total} events</li>
                }}
            </ul>
            <p>Next: in Settings, tick your class calendar or courses.</p>
        }}
        <Link to="/settings" className="btn">Go to Settings</Link>
    </div>
}
