"""Reading a partial-update `changes` dict safely.

Why update endpoints take `changes: dict` instead of optional parameters:
in jac 0.37.14 an omitted `x: str | None = None` endpoint parameter arrives as
the STRING "None" rather than None (verified with a probe endpoint), so
"was this field sent?" can't be answered from optional parameters. A dict
holding only the fields to change answers it directly.
"""

"""Reject keys we don't know, so typos fail loudly instead of being ignored."""
def check_keys(changes: dict, allowed: list[str]) -> None {
    unknown = [k for k in changes if k not in allowed];
    if unknown {
        raise ValueError(f"Unknown field(s) {unknown}; allowed: {allowed}");
    }
}

def get_str(changes: dict, key: str, current: str) -> str {
    if key not in changes {
        return current;
    }
    value = changes[key];
    if not isinstance(value, str) {
        raise ValueError(f"{key} must be a string");
    }
    return value;
}

def get_int(changes: dict, key: str, current: int) -> int {
    if key not in changes {
        return current;
    }
    value = changes[key];
    # bool is a subclass of int in Python; don't accept true/false as numbers.
    if isinstance(value, bool) or not isinstance(value, int) {
        raise ValueError(f"{key} must be a whole number");
    }
    return value;
}

def get_str_list(changes: dict, key: str, current: list[str]) -> list[str] {
    if key not in changes {
        return current;
    }
    value = changes[key];
    if not isinstance(value, list) or not all(isinstance(v, str) for v in value) {
        raise ValueError(f"{key} must be a list of strings");
    }
    return value;
}
