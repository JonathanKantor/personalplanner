"""Input helpers that work around a jac 0.37.14 endpoint quirk.

Verified with probe endpoints: when a caller OMITS a parameter that has a
default, the server passes the default converted to a string:
    x: str | None = None   ->  "None"
    n: int = 7             ->  "7"
    b: bool = False        ->  "False"   (which is truthy!)
Only `str` defaults arrive intact. Hence:
- update endpoints take a `changes: dict` holding only the fields to change;
- int parameters with defaults go through `as_int`.
"""

"""Accept an int, or a numeric string (an omitted default arrives as one)."""
def as_int(value: any, name: str) -> int {
    if isinstance(value, bool) {
        raise ValueError(f"{name} must be a whole number");
    }
    if isinstance(value, int) {
        return value;
    }
    try {
        return int(str(value));
    } except ValueError {
        raise ValueError(f"{name} must be a whole number");
    }
}

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
