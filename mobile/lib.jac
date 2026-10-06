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

"""Minutes past midnight -> "10:30" (no am/pm, like the web calendar)."""
def:pub clock12(minutes: int) -> str {
    h = (minutes // 60) % 12;
    m = minutes % 60;
    return str(12 if h == 0 else h) + ":" + _pad(m);
}

"""Minutes past midnight -> "11:59pm" / "9am"."""
def:pub clock_ampm(minutes: int) -> str {
    h = (minutes // 60) % 24;
    m = minutes % 60;
    return str(12 if h % 12 == 0 else h % 12) + ((":" + _pad(m)) if m else "") + ("am" if h < 12 else "pm");
}

"""Minutes past midnight -> "09:30" (for time inputs and the server)."""
def:pub hhmm(minutes: int) -> str {
    return _pad(minutes // 60) + ":" + _pad(minutes % 60);
}

def:pub time_range(start_min: int, end_min: int) -> str {
    return clock12(start_min) + " – " + clock12(end_min);
}

"""Monday of the week containing `day`."""
def:pub monday_of(day: str) -> str {
    d: any = new(Date, day + "T12:00:00");  # jac:ignore[E1053]
    back = (d.getDay() + 6) % 7;             # JS: Sunday = 0
    return add_days(day, -back);
}

"""Day of month without a leading zero: "2026-10-05" -> "5"."""
def:pub day_num(day: str) -> str {
    return day[8:10].lstrip("0");
}

"""A stored UTC time as local ["YYYY-MM-DD", "HH:MM"] in timezone `tz`
(falls back to the phone's own timezone if `tz` isn't supported)."""
def:pub local_parts(iso: str, tz: str) -> list[str] {
    d: any = new(Date, iso);  # jac:ignore[E1053]
    try {
        s = str(d.toLocaleString("sv-SE", {"timeZone": tz, "hour12": False}));   # "2026-10-07 23:00:00"
        return [s[0:10], s[11:16]];
    } except Exception {
        return [_fmt(d), _pad(d.getHours()) + ":" + _pad(d.getMinutes())];
    }
}

"""Is `t` a valid 24-hour "HH:MM"?"""
def:pub valid_hhmm(t: str) -> bool {
    parts = t.strip().split(":");
    if len(parts) != 2 or not parts[0].isdigit() or not parts[1].isdigit() {
        return False;
    }
    return int(parts[0]) < 24 and int(parts[1]) < 60 and len(parts[1]) == 2;
}

"""Month and day: "2026-10-07" -> "Oct 7"."""
def:pub month_day(day: str) -> str {
    d: any = new(Date, day + "T12:00:00");  # jac:ignore[E1053]
    return d.toLocaleDateString("en-US", {"month": "short", "day": "numeric"});
}

