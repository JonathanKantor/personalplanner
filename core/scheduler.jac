"""The scheduling engine: a deterministic, greedy slot-filler.

Pure functions only - no graph, no clock, no database - so the same input
always gives the same output and the tests can use fixed dates.

Algorithm
1. Free time = working hours on working days, minus calendar events and
   accepted blocks (each padded by the minimum break), clipped to the window.
2. Tasks are placed one at a time, most urgent first: earliest due date, then
   higher priority, then shorter duration (so small tasks aren't crowded out).
3. Each task takes the earliest free time before its deadline - on each day,
   the preferred study window first - in sessions of 30 to 120 minutes, never
   exceeding the daily focus cap.
4. Whatever doesn't fit is reported with the reason.
"""

import from datetime { datetime, date, time, timedelta }
import from core.timeutil { zone, parse_hhmm }

glob MIN_SESSION: int = 30,          # never suggest a block shorter than this...
     MAX_SESSION: int = 120,         # ...or longer than this
     DAY_CODES: list[str] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
     PRIORITY_RANK: dict[str, int] = {"high": 0, "medium": 1, "low": 2};

# ------------------------------------------------------------------ data

obj Interval {
    has start: datetime, end: datetime;

    def minutes -> int {
        return int((self.end - self.start).total_seconds() // 60);
    }
}

obj SchedPrefs {
    has tz: str,
        work_start: str = "09:00",
        work_end: str = "21:00",
        days_off: list[str] = [],
        preferred_start: str = "",
        preferred_end: str = "",
        min_break_minutes: int = 15,
        max_focus_minutes_per_day: int = 360;
}

obj SchedTask {
    has id: str,
        title: str,
        due: datetime,
        priority: str,                       # "high" | "medium" | "low"
        minutes: int,                        # still to schedule
        avoid: list[Interval] = [];          # slots the user rejected for this task
}

obj Placement {
    has task_id: str,
        title: str,
        start: datetime,
        end: datetime,
        session: int,
        sessions_total: int,
        reason: str;
}

obj Unplaced {
    has task_id: str,
        title: str,
        minutes_needed: int,
        minutes_placed: int,
        reason: str;
}

obj Plan {
    has placements: list[Placement] = [],
        unplaced: list[Unplaced] = [];
}

# ------------------------------------------------------------------ interval math

"""Remove every `cut` from every slot. Returns what's left, sorted."""
def subtract(slots: list[Interval], cuts: list[Interval]) -> list[Interval] {
    result = slots;
    for c in cuts {
        next: list[Interval] = [];
        for s in result {
            if c.end <= s.start or c.start >= s.end {
                next.append(s);                                   # no overlap
                continue;
            }
            if s.start < c.start {
                next.append(Interval(start=s.start, end=c.start));  # piece before
            }
            if c.end < s.end {
                next.append(Interval(start=c.end, end=s.end));      # piece after
            }
        }
        result = next;
    }
    result.sort(key=lambda (i: Interval) { i.start; });
    return result;
}

def intersect(a: Interval, b: Interval) -> Interval | None {
    s = max(a.start, b.start);
    e = min(a.end, b.end);
    return Interval(start=s, end=e) if s < e else None;
}

"""Working hours on each working day of the window, as aware datetimes.
`datetime.combine(day, time, tzinfo=...)` gives the correct UTC offset for
each day, so 09:00 stays 09:00 across a daylight-saving change."""
def working_hours(prefs: SchedPrefs, window: Interval) -> list[Interval] {
    tz = zone(prefs.tz);
    off = [d.lower()[:3] for d in prefs.days_off];
    ws = parse_hhmm(prefs.work_start);
    we = parse_hhmm(prefs.work_end);
    out: list[Interval] = [];
    day = window.start.astimezone(tz).date();
    last = window.end.astimezone(tz).date();
    while day <= last {
        if DAY_CODES[day.weekday()] not in off {
            hours = Interval(
                start=datetime.combine(day, ws, tzinfo=tz),
                end=datetime.combine(day, we, tzinfo=tz)
            );
            clipped = intersect(hours, window);
            if clipped is not None {
                out.append(clipped);
            }
        }
        day = day + timedelta(days=1);
    }
    return out;
}

"""Free time: working hours minus busy intervals, keeping `min_break_minutes`
clear on both sides of every busy interval."""
def free_slots(prefs: SchedPrefs, busy: list[Interval], window: Interval) -> list[Interval] {
    gap = timedelta(minutes=prefs.min_break_minutes);
    padded = [Interval(start=b.start - gap, end=b.end + gap) for b in busy];
    return subtract(working_hours(prefs, window), padded);
}

"""The order free time is tried in: day by day, and within each day the
preferred study window first, then the rest of the day."""
def candidate_order(free: list[Interval], prefs: SchedPrefs) -> list[Interval] {
    if not prefs.preferred_start {
        return free;
    }
    tz = zone(prefs.tz);
    ps = parse_hhmm(prefs.preferred_start);
    pe = parse_hhmm(prefs.preferred_end);
    out: list[Interval] = [];
    by_day: dict[date, list[Interval]] = {};
    for s in free {
        by_day.setdefault(s.start.astimezone(tz).date(), []).append(s);
    }
    for day in sorted(by_day.keys()) {
        pref = Interval(start=datetime.combine(day, ps, tzinfo=tz), end=datetime.combine(day, pe, tzinfo=tz));
        inside: list[Interval] = [];
        for s in by_day[day] {
            part = intersect(s, pref);
            if part is not None {
                inside.append(part);
            }
        }
        out += inside + subtract(by_day[day], [pref]);
    }
    return out;
}

# ------------------------------------------------------------------ text

"""9:00 -> "9am", 14:30 -> "2:30pm"."""
def clock(dt: datetime) -> str {
    h = dt.hour % 12 or 12;
    suffix = "am" if dt.hour < 12 else "pm";
    return f"{h}{suffix}" if dt.minute == 0 else f"{h}:{dt.minute:02d}{suffix}";
}

def day_name(dt: datetime) -> str {
    return dt.strftime("%A");
}

def _reason(free: Interval, due: datetime, priority: str, session: int, total: int, tz: str) -> str {
    z = zone(tz);
    fs = free.start.astimezone(z);
    fe = free.end.astimezone(z);
    d = due.astimezone(z);
    text = f"Free {clock(fs)}-{clock(fe)} {day_name(fs)}, due {day_name(d)} {clock(d)}, {priority} priority";
    if total > 1 {
        text += f" (session {session} of {total})";
    }
    return text;
}

# ------------------------------------------------------------------ planning

"""The order tasks are placed in: due date, then priority, then duration.
Title and id break any remaining ties so the result never depends on input order."""
def task_order(t: SchedTask) -> tuple {
    return (t.due, PRIORITY_RANK.get(t.priority, 1), t.minutes, t.title, t.id);
}

"""Length of the next session for a task with `remaining` minutes when
`room` minutes are available, or 0 if it shouldn't go here."""
def session_length(remaining: int, room: int) -> int {
    length = min(remaining, MAX_SESSION, room);
    leftover = remaining - length;
    if 0 < leftover and leftover < MIN_SESSION {
        # Don't leave a stub shorter than a session: 130 min -> 100 + 30, not 120 + 10.
        length = remaining - MIN_SESSION;
    }
    return length if length >= min(MIN_SESSION, remaining) else 0;
}

"""Place `tasks` into free time.

busy:          calendar events + accepted blocks (all tasks)
focus_used:    minutes already accepted per local day, counted against the cap
window:        only plan inside this interval (start is usually "now")
"""
def plan(
    tasks: list[SchedTask],
    prefs: SchedPrefs,
    busy: list[Interval],
    focus_used: dict[date, int],
    window: Interval
) -> Plan {
    tz = zone(prefs.tz);
    gap = timedelta(minutes=prefs.min_break_minutes);
    free = free_slots(prefs, busy, window);
    used: dict[date, int] = dict(focus_used);
    result = Plan();

    for t in sorted(tasks, key=task_order) {
        if t.minutes <= 0 {
            continue;
        }
        if t.due <= window.start {
            result.unplaced.append(Unplaced(
                task_id=t.id, title=t.title, minutes_needed=t.minutes, minutes_placed=0,
                reason=f"Its due date ({day_name(t.due.astimezone(tz))} {clock(t.due.astimezone(tz))}) has already passed"
            ));
            continue;
        }
        remaining = t.minutes;
        placed: list[tuple[Interval, Interval]] = [];    # (block, free time it came from)
        while remaining > 0 {
            found = False;
            # Only time before the deadline, and not slots the user rejected.
            usable = subtract(
                [s for s in free if s.start < t.due], t.avoid + [Interval(start=t.due, end=window.end + timedelta(days=1))]
            );
            for piece in candidate_order(usable, prefs) {
                day = piece.start.astimezone(tz).date();
                room = min(piece.minutes(), prefs.max_focus_minutes_per_day - used.get(day, 0));
                length = session_length(remaining, room);
                if length == 0 {
                    continue;
                }
                block = Interval(start=piece.start, end=piece.start + timedelta(minutes=length));
                placed.append((block, piece));
                used[day] = used.get(day, 0) + length;
                remaining -= length;
                # The block and a break after it are no longer free.
                free = subtract(free, [Interval(start=block.start - gap, end=block.end + gap)]);
                found = True;
                break;
            }
            if not found {
                break;
            }
        }

        # Number sessions in time order (the preferred window is filled first,
        # so placement order can differ from clock order).
        placed.sort(key=lambda (pair: tuple[Interval, Interval]) { pair[0].start; });
        total = len(placed);
        for (i, (block, piece)) in enumerate(placed) {
            result.placements.append(Placement(
                task_id=t.id, title=t.title, start=block.start, end=block.end,
                session=i + 1, sessions_total=total,
                reason=_reason(piece, t.due, t.priority, i + 1, total, prefs.tz)
            ));
        }
        if remaining > 0 {
            result.unplaced.append(Unplaced(
                task_id=t.id, title=t.title, minutes_needed=t.minutes,
                minutes_placed=t.minutes - remaining,
                reason=_why_not(t, remaining, free, used, prefs, window)
            ));
        }
    }
    result.placements.sort(key=lambda (p: Placement) { p.start; });
    return result;
}

"""Explain why `remaining` minutes of a task didn't fit."""
def _why_not(
    t: SchedTask, remaining: int, free: list[Interval], used: dict[date, int],
    prefs: SchedPrefs, window: Interval
) -> str {
    tz = zone(prefs.tz);
    due = t.due.astimezone(tz);
    due_text = f"{day_name(due)} {clock(due)}";
    placed = t.minutes - remaining;
    head = f"Only {placed} of {t.minutes} min fit before {due_text}" if placed else f"No room before {due_text}";
    if t.due > window.end {
        return f"{head}: the planning window ends {day_name(window.end.astimezone(tz))}; plan again later or plan further ahead";
    }
    # Is there free time left that the daily cap blocked?
    before_due = subtract([s for s in free if s.start < t.due], [Interval(start=t.due, end=t.due + timedelta(days=1))]);
    left = sum([s.minutes() for s in before_due if s.minutes() >= min(MIN_SESSION, remaining)]);
    if left >= min(MIN_SESSION, remaining) {
        return f"{head}: the {prefs.max_focus_minutes_per_day}-min daily focus limit is reached on the remaining free days";
    }
    return f"{head}: the free time is taken by classes, events, and more urgent tasks";
}
