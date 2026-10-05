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
