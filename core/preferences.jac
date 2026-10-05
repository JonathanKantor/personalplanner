"""Preferences endpoints.

`def:protect` = an HTTP endpoint (POST /function/<name>) that requires a
logged-in user (JWT). Inside it, `root` is THAT user's root node, so each user
only ever sees and changes their own data. (`:protect` and `:priv` require the
same login; `:protect` additionally lets other modules in this project import
the function, which web/main.jac needs in order to register it.
`def:pub` would allow anonymous callers, so it is never used for user data.)
"""

import from core.models { Preferences, PreferencesView }
import from core.timeutil { zone, parse_hhmm }
import from core.changes { check_keys, get_str, get_int, get_str_list }

glob WEEKDAYS: list[str] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

"""Return this user's Preferences node, creating it with defaults on first use.

The leading underscore keeps this helper off the HTTP API.
"""
def _prefs -> Preferences {
    # [root -->] = nodes connected from root; [?:Preferences] filters by type.
    found = [root -->][?:Preferences];
    if found {
        return found[0];
    }
    # `++>` connects a new node to root, which is what makes it persistent.
    return root ++> Preferences();
}

def _view(p: Preferences) -> PreferencesView {
    return PreferencesView(
        timezone=p.timezone,
        work_start=p.work_start,
        work_end=p.work_end,
        days_off=p.days_off,
        preferred_start=p.preferred_start,
        preferred_end=p.preferred_end,
        min_break_minutes=p.min_break_minutes,
        max_focus_minutes_per_day=p.max_focus_minutes_per_day
    );
}

def:protect get_preferences -> PreferencesView {
    return _view(_prefs());
}

glob PREF_FIELDS: list[str] = [
    "timezone", "work_start", "work_end", "days_off", "preferred_start",
    "preferred_end", "min_break_minutes", "max_focus_minutes_per_day"
];

"""Change some preferences, e.g. changes={"days_off": ["sat", "sun"]}.
Fields not in `changes` keep their value (see core/changes.jac for why a dict)."""
def:protect update_preferences(changes: dict) -> PreferencesView {
    check_keys(changes, PREF_FIELDS);
    p = _prefs();
    # Validate everything first, so a bad value changes nothing.
    tz = get_str(changes, "timezone", p.timezone);
    _ = zone(tz);
    start = get_str(changes, "work_start", p.work_start);
    end = get_str(changes, "work_end", p.work_end);
    if parse_hhmm(start) >= parse_hhmm(end) {
        raise ValueError("work_start must be before work_end");
    }
    pref_start = get_str(changes, "preferred_start", p.preferred_start);
    pref_end = get_str(changes, "preferred_end", p.preferred_end);
    if bool(pref_start) != bool(pref_end) {
        raise ValueError("Set both preferred_start and preferred_end, or neither");
    }
    if pref_start and parse_hhmm(pref_start) >= parse_hhmm(pref_end) {
        raise ValueError("preferred_start must be before preferred_end");
    }
    days = get_str_list(changes, "days_off", p.days_off);
    days = [d.strip().lower()[:3] for d in days];
    for d in days {
        if d not in WEEKDAYS {
            raise ValueError(f"Unknown day '{d}'; use mon, tue, wed, thu, fri, sat, sun");
        }
    }
    gap = get_int(changes, "min_break_minutes", p.min_break_minutes);
    cap = get_int(changes, "max_focus_minutes_per_day", p.max_focus_minutes_per_day);
    if gap < 0 or cap <= 0 or cap > 24 * 60 {
        raise ValueError("min_break_minutes must be >= 0 and max focus between 1 and 1440 minutes");
    }

    p.timezone = tz;
    p.work_start = start;
    p.work_end = end;
    p.days_off = days;
    p.preferred_start = pref_start;
    p.preferred_end = pref_end;
    p.min_break_minutes = gap;
    p.max_focus_minutes_per_day = cap;
    # Imported here, not at the top: core.planning imports this module.
    import from core.planning { replan_if_pending }
    replan_if_pending();
    return _view(p);
}
