"""Google Calendar: OAuth connect and read-only sync.

Flow (standard OAuth "authorization code" flow):
1. google_auth_url() returns a Google sign-in link. The web app opens it.
2. After you approve, Google redirects the browser to GOOGLE_REDIRECT_URI
   (the web app's /oauth/callback page) with ?code=...&state=...
3. That page calls connect_google(code, state). The server swaps the code for a
   refresh token, stores it on this user's GoogleAccount node, and syncs.
4. Later syncs use the refresh token to get a short-lived access token.

Scope is calendar.readonly: the planner can read events but never change them.
Client id/secret come from environment variables (see .env.example), never
from code or git. All HTTP calls use the `requests` Python library.
"""

import os;
import secrets;
import requests;
import from urllib.parse { urlencode, quote }
import from datetime { datetime, timedelta }
import from core.models { GoogleAccount, Calendar, Occurrence, SyncResult }
import from core.timeutil { to_iso, now_utc, zone }
import from core.preferences { _prefs }
import from core.calendars {
    _calendars, _events, _get_or_create_calendar, _apply_sync, sync_window
}

glob SCOPE: str = "https://www.googleapis.com/auth/calendar.readonly",
     AUTH_URL: str = "https://accounts.google.com/o/oauth2/v2/auth",
     TOKEN_URL: str = "https://oauth2.googleapis.com/token",
     API: str = "https://www.googleapis.com/calendar/v3";

def _config -> dict[str, str] {
    cfg = {
        "client_id": os.environ.get("GOOGLE_CLIENT_ID", ""),
        "client_secret": os.environ.get("GOOGLE_CLIENT_SECRET", ""),
        "redirect_uri": os.environ.get(
            "GOOGLE_REDIRECT_URI", "http://localhost:8000/oauth/callback"
        )
    };
    if not cfg["client_id"] or not cfg["client_secret"] {
        raise ValueError(
            "Google sync is not configured: set GOOGLE_CLIENT_ID and "
            "GOOGLE_CLIENT_SECRET (see README). Use .ics import meanwhile."
        );
    }
    return cfg;
}

def _account -> GoogleAccount {
    found = [root -->][?:GoogleAccount];
    if found {
        return found[0];
    }
    return root ++> GoogleAccount();
}

def _post_token(data: dict) -> dict {
    try {
        resp = requests.post(TOKEN_URL, data=data, timeout=20);
    } except requests.RequestException as e {
        raise ValueError(f"Could not reach Google: {str(e)}");
    }
    body = resp.json();
    if resp.status_code != 200 {
        raise ValueError(f"Google rejected the request: {body.get('error_description') or body.get('error')}");
    }
    return body;
}

def _access_token(acct: GoogleAccount) -> str {
    if not acct.refresh_token {
        raise ValueError("Google is not connected; connect it in Settings first");
    }
    cfg = _config();
    body = _post_token({
        "client_id": cfg["client_id"],
        "client_secret": cfg["client_secret"],
        "refresh_token": acct.refresh_token,
        "grant_type": "refresh_token"
    });
    return body["access_token"];
}

def _get(url: str, token: str, params: dict) -> dict {
    try {
        resp = requests.get(
            url, params=params, headers={"Authorization": f"Bearer {token}"}, timeout=30
        );
    } except requests.RequestException as e {
        raise ValueError(f"Could not reach Google Calendar: {str(e)}");
    }
    if resp.status_code != 200 {
        raise ValueError(f"Google Calendar error {resp.status_code}: {resp.text[:200]}");
    }
    return resp.json();
}

"""Convert one item from Google's events.list into an Occurrence.
Returns None for things that shouldn't block time: cancelled events and events
marked "Show as: Available" (transparency = transparent)."""
def google_event_to_occurrence(item: dict, tz_name: str) -> Occurrence | None {
    if item.get("status") == "cancelled" or item.get("transparency") == "transparent" {
        return None;
    }
    start = item.get("start", {});
    end = item.get("end", {});
    all_day = "date" in start;
    if all_day {
        # All-day events give plain dates; the end date is exclusive.
        s = datetime.fromisoformat(start["date"]).replace(tzinfo=zone(tz_name));
        e = datetime.fromisoformat(end["date"]).replace(tzinfo=zone(tz_name));
    } else {
        s = datetime.fromisoformat(start["dateTime"]);
        e = datetime.fromisoformat(end["dateTime"]);
    }
    return Occurrence(
        # With singleEvents=true each occurrence of a recurring event has its
        # own stable id, and recurringEventId names the series.
        external_id=item["id"],
        series_id=item.get("recurringEventId", ""),
        title=item.get("summary", "(no title)"),
        start=to_iso(s),
        end=to_iso(e),
        all_day=all_day
    );
}

def _sync_google_calendar(cal: Calendar) -> SyncResult {
    token = _access_token(_account());
    (start, end) = sync_window();
    tz = _prefs().timezone;
    occurrences: list[Occurrence] = [];
    page_token = "";
    while True {
        params = {
            "singleEvents": "true",          # Google expands recurring events for us
            "orderBy": "startTime",
            "timeMin": to_iso(start),
            "timeMax": to_iso(end),
            "maxResults": "2500"
        };
        if page_token {
            params["pageToken"] = page_token;
        }
        page = _get(f"{API}/calendars/{quote(cal.external_id, safe='')}/events", token, params);
        for item in page.get("items", []) {
            occ = google_event_to_occurrence(item, tz);
            if occ is not None {
                occurrences.append(occ);
            }
        }
        page_token = page.get("nextPageToken", "");
        if not page_token {
            break;
        }
    }
    return _apply_sync(cal, occurrences, start, end);
}

# ------------------------------------------------------------------ endpoints

def:protect google_status -> dict[str, bool] {
    configured = bool(os.environ.get("GOOGLE_CLIENT_ID")) and bool(os.environ.get("GOOGLE_CLIENT_SECRET"));
    accts = [root -->][?:GoogleAccount];
    return {"configured": configured, "connected": bool(accts) and bool(accts[0].refresh_token)};
}

"""Step 1: the Google sign-in link. `state` is a random value we check in
step 3 so a forged redirect can't attach someone else's Google account."""
def:protect google_auth_url -> str {
    cfg = _config();
    acct = _account();
    acct.oauth_state = secrets.token_urlsafe(24);
    query = urlencode({
        "client_id": cfg["client_id"],
        "redirect_uri": cfg["redirect_uri"],
        "response_type": "code",
        "scope": SCOPE,
        "access_type": "offline",    # ask for a refresh token
        "prompt": "consent",         # always return one, even on re-connect
        "state": acct.oauth_state
    });
    return f"{AUTH_URL}?{query}";
}

"""Step 3: finish connecting, then import the calendars selected in Google."""
def:protect connect_google(code: str, state: str) -> list[SyncResult] {
    cfg = _config();
    acct = _account();
    if not acct.oauth_state or not secrets.compare_digest(state, acct.oauth_state) {
        raise ValueError("Sign-in link expired or invalid; start Connect Google again");
    }
    acct.oauth_state = "";
    body = _post_token({
        "code": code,
        "client_id": cfg["client_id"],
        "client_secret": cfg["client_secret"],
        "redirect_uri": cfg["redirect_uri"],
        "grant_type": "authorization_code"
    });
    if "refresh_token" in body {
        acct.refresh_token = body["refresh_token"];
    }
    acct.connected_at = to_iso(now_utc());

    listing = _get(f"{API}/users/me/calendarList", body["access_token"], {});
    results: list[SyncResult] = [];
    for item in listing.get("items", []) {
        if item.get("selected") {     # only calendars shown in Google Calendar
            cal = _get_or_create_calendar("google", item["id"], item.get("summary", item["id"]));
            results.append(_sync_google_calendar(cal));
        }
    }
    return results;
}

"""Forget the Google connection and remove Google calendars from the planner.
(To fully revoke access, also remove the app at myaccount.google.com/permissions.)"""
def:protect disconnect_google -> bool {
    for a in [root -->][?:GoogleAccount] {
        del a;
    }
    for c in _calendars() {
        if c.source == "google" {
            for e in _events(c) {
                del e;
            }
            del c;
        }
    }
    return True;
}
