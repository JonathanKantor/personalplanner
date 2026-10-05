"""Small client-side helpers shared by the pages.

Pinned to the client in jac.toml; `def:pub` here means "exported to other
client modules" (in browser code, pub is an export, not an endpoint).
"""

"""The readable part of an error thrown by a server call.

A failed call throws an Error whose message looks like
    Function create_task failed: {"ok": false, ..., "error": {"message": "..."}}
so pull out the server's own message (the ValueError text from core/)."""
def:pub error_text(e: any) -> str {
    msg: str = e.message if e and e.message else str(e);
    start = msg.find("{");
    if start >= 0 {
        try {
            body: any = JSON.parse(msg[start:]);  # jac:ignore[E1032]  (browser global)
            if body and body.error and body.error.message {
                msg = body.error.message;
            }
        } except Exception {}
    }
    if "UNAUTHORIZED" in msg or "Unauthorized" in msg {
        return "Your session expired. Please log in again.";
    }
    return msg;
}

"""Minutes past midnight -> "14:30"."""
def:pub hhmm(minutes: int) -> str {
    h = minutes // 60;
    m = minutes % 60;
    return ("0" if h < 10 else "") + str(h) + ":" + ("0" if m < 10 else "") + str(m);
}

"""A stored UTC time as the local "YYYY-MM-DDTHH:MM" that <input type=datetime-local>
expects. (The Swedish locale happens to format dates as YYYY-MM-DD HH:MM.)"""
def:pub local_input(iso: str, tz: str) -> str {
    d: any = new(Date, iso);  # jac:ignore[E1053]
    return d.toLocaleString("sv-SE", {"timeZone": tz}).replace(" ", "T")[0:16];
}

"""The logged-in user's username, from the server's built-in /user/me
(used when no display name is set). "" if it can't be read."""
async def:pub current_username -> str {
    try {
        token: any = localStorage.getItem("jac_token");  # jac:ignore[E1032]
        resp: any = await fetch("/user/me", {"headers": {"Authorization": "Bearer " + str(token)}});  # jac:ignore[E1032]
        body: any = await resp.json();
        info: any = body.data if body.data else body;
        for ident in info.identities {
            if ident.type == "username" {
                return ident.value;
            }
        }
    } except Exception {}
    return "";
}

"""Today in the user's timezone, e.g. "Mon, Oct 5"."""
def:pub today_label(tz: str) -> str {
    d: any = new(Date);  # jac:ignore[E1053]
    return d.toLocaleDateString("en-US", {"weekday": "short", "month": "short", "day": "numeric", "timeZone": tz});
}

"""Minutes past midnight -> 12-hour time without am/pm: 810 -> "1:30", 600 -> "10:00"."""
def:pub clock12(minutes: int) -> str {
    h = (minutes // 60) % 12;
    m = minutes % 60;
    return str(12 if h == 0 else h) + ":" + ("0" if m < 10 else "") + str(m);
}

"""A time range like the calendar shows it: "10:30 – 11:30"."""
def:pub time_range(start_min: int, end_min: int) -> str {
    return clock12(start_min) + " – " + clock12(end_min);
}

"""Hour label for the calendar gutter: 480 -> "8AM", 780 -> "1PM"."""
def:pub hour_label(minutes: int) -> str {
    h = minutes // 60;
    return str(12 if h % 12 == 0 else h % 12) + ("AM" if h < 12 or h == 24 else "PM");
}

"""A timezone's everyday name, e.g. "America/Detroit" -> "Eastern Time"."""
def:pub tz_name(tz: str) -> str {
    try {
        fmt: any = new(Intl.DateTimeFormat, "en-US", {"timeZone": tz, "timeZoneName": "longGeneric"});  # jac:ignore[E1053,E1032]
        for part in fmt.formatToParts(new(Date)) {  # jac:ignore[E1053]
            if part.type == "timeZoneName" {
                return part.value;
            }
        }
    } except Exception {}
    return tz;
}

"""Minutes past midnight right now in timezone `tz`."""
def:pub now_minutes(tz: str) -> int {
    d: any = new(Date);  # jac:ignore[E1053]
    parts: any = d.toLocaleTimeString("en-GB", {"timeZone": tz, "hour": "2-digit", "minute": "2-digit", "hour12": False}).split(":");
    return int(parts[0]) * 60 + int(parts[1]);
}

"""True when a key press is typing into a field, so single-key shortcuts
(T, N, J, K...) must not fire."""
def:pub typing_in_field(e: any) -> bool {
    el: any = e.target;
    tag = str(el.tagName or "");
    return tag == "INPUT" or tag == "TEXTAREA" or tag == "SELECT" or el.isContentEditable == True;
}

"""The shortcut-modifier label for this computer: "⌘" on a Mac, else "Ctrl"."""
def:pub mod_key -> str {
    plat: any = navigator.platform;  # jac:ignore[E1032]
    return "⌘" if "Mac" in str(plat) else "Ctrl";
}
