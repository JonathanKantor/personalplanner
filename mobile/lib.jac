"""Small client-side helpers for the mobile app.

A `mobile` app has no server of its own, so everything here is client code;
`def:pub` means "exported to the screens". Dates are local "YYYY-MM-DD"
strings, built with the JavaScript Date API (`new(Date, ...)` is Jac's way of
calling a JS constructor). Browser/RN globals have no type info for
`jac check`, hence the `any` annotations.
"""

def _pad(n: int) -> str {
    return ("0" if n < 10 else "") + str(n);
}

def _fmt(d: any) -> str {
    return str(d.getFullYear()) + "-" + _pad(d.getMonth() + 1) + "-" + _pad(d.getDate());
}

"""Today's local date, e.g. "2026-10-05"."""
def:pub today_str -> str {
    return _fmt(new(Date));  # jac:ignore[E1053]
}

"""`day` plus `n` days (n may be negative)."""
def:pub add_days(day: str, n: int) -> str {
    d: any = new(Date, day + "T12:00:00");  # jac:ignore[E1053]
    d.setDate(d.getDate() + n);
    return _fmt(d);
}

"""Short weekday name, e.g. "Wed"."""
def:pub weekday(day: str) -> str {
    d: any = new(Date, day + "T12:00:00");  # jac:ignore[E1053]
    return d.toLocaleDateString("en-US", {"weekday": "short"});
}

"""The readable part of an error from a walker call. Bridge errors carry the
server's message (the ValueError text from core/) in `detail` or inside a
JSON body in `message`."""
def:pub error_text(e: any) -> str {
    msg: str = "";
    if e and e.detail {
        msg = str(e.detail);
    } elif e and e.message {
        msg = e.message;
    } else {
        msg = str(e);
    }
    start = msg.find("{");
    if start >= 0 {
        try {
            body: any = JSON.parse(msg[start:]);  # jac:ignore[E1032]  (browser global)
            if body and body.error and body.error.message {
                msg = body.error.message;
            } elif body and body.message {
                msg = body.message;
            }
        } except Exception {}
    }
    if "UNAUTHORIZED" in msg or "Unauthorized" in msg or (e and e.status == 401) {
        return "Your session expired. Please log in again.";
    }
    if "Failed to fetch" in msg or "Network" in msg {
        return "Can't reach the planner server. Is it running?";
    }
    return msg;
}
