"""Scheduler tests (annex of core/scheduler.jac; run: jac test core/scheduler.jac).

Every test uses fixed dates in the week of Monday 2026-10-19, America/Detroit.
"""

import from datetime { datetime, timedelta, date }
import from zoneinfo { ZoneInfo }

glob TZ: str = "America/Detroit";

"""A local time on a day of the test week: at(1, "14:00") = Tue Oct 20 2pm."""
def at(day: int, hhmm: str) -> datetime {
    (h, m) = [int(x) for x in hhmm.split(":")];
    return datetime(2026, 10, 19 + day, h, m, tzinfo=ZoneInfo(TZ));
}

def iv(day: int, a: str, b: str) -> Interval {
    return Interval(start=at(day, a), end=at(day, b));
}

def prefs(**kw: any) -> SchedPrefs {
    base = {"tz": TZ, "work_start": "09:00", "work_end": "17:00", "min_break_minutes": 0, "max_focus_minutes_per_day": 480};
    base.update(kw);
    return SchedPrefs(**base);
}

def task(id: str, minutes: int, due: datetime, priority: str = "medium") -> SchedTask {
    return SchedTask(id=id, title=id, due=due, priority=priority, minutes=minutes);
}

"""The whole test week, starting Monday 9am. (A function, not a glob: globs in
a test annex are evaluated before the module's own declarations exist.)"""
def week -> Interval {
    return Interval(start=at(0, "09:00"), end=at(7, "00:00"));
}

def hours(slots: list[Interval]) -> list[str] {
    # strftime rather than an f-string format spec: jac 0.37.14 drops the
    # space inside `{dt:%a %H:%M}`.
    z = ZoneInfo(TZ);
    return [s.start.astimezone(z).strftime("%a %H:%M") + "-" + s.end.astimezone(z).strftime("%H:%M") for s in slots];
}

# ------------------------------------------------------------------ free slots

test "free time is working hours minus events" {
    one_day = Interval(start=at(0, "00:00"), end=at(1, "00:00"));
    free = free_slots(prefs(), [iv(0, "10:00", "11:00"), iv(0, "13:00", "14:30")], one_day);
    assert hours(free) == ["Mon 09:00-10:00", "Mon 11:00-13:00", "Mon 14:30-17:00"], hours(free);
}

test "breaks are kept around events" {
    one_day = Interval(start=at(0, "00:00"), end=at(1, "00:00"));
    free = free_slots(prefs(min_break_minutes=15), [iv(0, "10:00", "11:00")], one_day);
    assert hours(free) == ["Mon 09:00-09:45", "Mon 11:15-17:00"], hours(free);
}

test "back-to-back classes leave no gap between them" {
    one_day = Interval(start=at(1, "00:00"), end=at(2, "00:00"));
    busy = [iv(1, "12:00", "13:30"), iv(1, "13:30", "14:30")];
    free = free_slots(prefs(min_break_minutes=15), busy, one_day);
    assert hours(free) == ["Tue 09:00-11:45", "Tue 14:45-17:00"], hours(free);
}

test "days off have no free time" {
    free = free_slots(prefs(days_off=["sat", "sun"]), [], week());
    assert {s.start.astimezone(ZoneInfo(TZ)).strftime("%a") for s in free} == {"Mon", "Tue", "Wed", "Thu", "Fri"};
}

test "window start clips today's free time" {
    window = Interval(start=at(0, "15:20"), end=at(1, "00:00"));
    assert hours(free_slots(prefs(), [], window)) == ["Mon 15:20-17:00"];
}

test "working hours stay local across the DST change" {
    # DST ends Sunday Nov 1 2026: 9am is 13:00 UTC on Saturday, 14:00 UTC on Monday.
    window = Interval(start=datetime(2026, 10, 31, tzinfo=ZoneInfo(TZ)), end=datetime(2026, 11, 3, tzinfo=ZoneInfo(TZ)));
    utc_hours = [s.start.astimezone(ZoneInfo("UTC")).hour for s in working_hours(prefs(), window)];
    assert utc_hours == [13, 14, 14], utc_hours;
}

# ------------------------------------------------------------------ placement

test "a task goes in the earliest free slot" {
    p = plan([task("essay", 60, at(2, "17:00"))], prefs(), [iv(0, "09:00", "12:00")], {}, week());
    assert len(p.placements) == 1 and not p.unplaced;
    assert hours([Interval(start=p.placements[0].start, end=p.placements[0].end)]) == ["Mon 12:00-13:00"];
}

test "never scheduled after the deadline" {
    # Mon is full; the task is due Tue 10am, so only Tue 9-10 works.
    busy = [iv(0, "09:00", "17:00")];
    p = plan([task("quiz prep", 60, at(1, "10:00"))], prefs(), busy, {}, week());
    assert len(p.placements) == 1;
    assert p.placements[0].end <= at(1, "10:00");
}

test "more urgent task gets the earlier slot" {
    later = task("later", 60, at(4, "17:00"));
    sooner = task("sooner", 60, at(1, "17:00"));
    p = plan([later, sooner], prefs(), [], {}, week());
    assert [x.task_id for x in p.placements] == ["sooner", "later"];
}

test "same due date: higher priority first, then shorter" {
    due = at(3, "17:00");
    tasks = [task("low", 30, due, "low"), task("long-high", 90, due, "high"), task("short-high", 30, due, "high")];
    p = plan(tasks, prefs(), [], {}, week());
    assert [x.task_id for x in p.placements] == ["short-high", "long-high", "low"];
}

test "back-to-back sessions of one task are joined into one block" {
    # 300 min with a free day: sessions 120 + 120 + 60 sit next to each
    # other, so they're shown as one 5-hour block (same task, same name).
    p = plan([task("project", 300, at(4, "17:00"))], prefs(min_break_minutes=15), [], {}, week());
    assert hours([Interval(start=x.start, end=x.end) for x in p.placements]) == ["Mon 09:00-14:00"], p.placements;
    assert p.placements[0].session == 1 and p.placements[0].sessions_total == 1;
    assert "session" not in p.placements[0].reason;
}

test "sessions are still split where free time is broken" {
    p = plan([task("project", 180, at(4, "17:00"))], prefs(), [iv(0, "11:00", "12:00")], {}, week());
    assert hours([Interval(start=x.start, end=x.end) for x in p.placements]) == ["Mon 09:00-11:00", "Mon 12:00-13:00"], p.placements;
    assert [x.session for x in p.placements] == [1, 2];
}

test "splitting never leaves a stub shorter than 30 minutes" {
    # 130 min, 2 free hours before an 11:00 class: 100 + 30 (not 120 + 10).
    p = plan([task("t", 130, at(4, "17:00"))], prefs(), [iv(0, "11:00", "12:00")], {}, week());
    minutes = [int((x.end - x.start).total_seconds() // 60) for x in p.placements];
    assert minutes == [100, 30], minutes;
}

test "short gaps are skipped" {
    # Only a 20-minute gap before 10:20; the 60-min task must go after the event.
    p = plan([task("t", 60, at(0, "17:00"))], prefs(), [iv(0, "09:20", "12:00")], {}, week());
    assert p.placements[0].start == at(0, "12:00");
}

test "daily focus cap is respected" {
    p = plan([task("big", 240, at(3, "17:00"))], prefs(max_focus_minutes_per_day=120), [], {}, week());
    days = [x.start.astimezone(ZoneInfo(TZ)).date() for x in p.placements];
    assert days == [date(2026, 10, 19), date(2026, 10, 20)], days;
}

test "accepted blocks are busy and count toward the cap" {
    accepted = iv(0, "09:00", "11:00");
    p = plan(
        [task("t", 60, at(4, "17:00"))], prefs(max_focus_minutes_per_day=120),
        [accepted], {date(2026, 10, 19): 120}, week()
    );
    # Monday's cap is used up by the accepted block, so it moves to Tuesday.
    assert p.placements[0].start == at(1, "09:00");
}

test "rejected slots are not suggested again" {
    t = task("t", 60, at(4, "17:00"));
    t.avoid = [iv(0, "09:00", "10:00")];
    p = plan([t], prefs(), [], {}, week());
    assert p.placements[0].start == at(0, "10:00");
}

test "preferred study window is tried first each day" {
    p = plan([task("t", 60, at(4, "17:00"))], prefs(preferred_start="14:00", preferred_end="17:00"), [], {}, week());
    assert p.placements[0].start == at(0, "14:00");
}

test "sessions are numbered in time order" {
    # Preferred window 14-17 fills first (90 min there), the rest lands earlier that day.
    p = plan(
        [task("t", 150, at(0, "23:00"))],
        prefs(preferred_start="14:00", preferred_end="15:30", work_end="17:00"), [], {}, week()
    );
    assert [x.session for x in p.placements] == [1, 2];
    assert p.placements[0].start < p.placements[1].start;
}

test "breaks are kept between suggested blocks" {
    tasks = [task("a", 60, at(0, "17:00")), task("b", 60, at(0, "17:00"))];
    p = plan(tasks, prefs(min_break_minutes=15), [], {}, week());
    assert p.placements[1].start - p.placements[0].end == timedelta(minutes=15);
}

# ------------------------------------------------------------------ can't fit

test "a task that cannot fit is reported with a reason" {
    busy = [iv(0, "09:00", "16:30")];
    p = plan([task("essay", 120, at(0, "17:00"))], prefs(), busy, {}, week());
    assert len(p.unplaced) == 1;
    u = p.unplaced[0];
    assert u.minutes_placed == 30 and u.minutes_needed == 120;
    assert "Only 30 of 120 min fit before Monday 5pm" in u.reason, u.reason;
    assert "classes, events" in u.reason;
    assert len(p.placements) == 1;       # the part that fits is still suggested
}

test "a past deadline is reported" {
    window = Interval(start=at(2, "09:00"), end=at(7, "00:00"));
    p = plan([task("late", 60, at(1, "17:00"))], prefs(), [], {}, window);
    assert not p.placements;
    assert "already passed" in p.unplaced[0].reason;
}

test "the reason names the daily cap when that is the limit" {
    p = plan([task("big", 300, at(1, "17:00"))], prefs(max_focus_minutes_per_day=60), [], {}, week());
    assert "daily focus limit" in p.unplaced[0].reason, p.unplaced[0].reason;
}

# ------------------------------------------------------------------ explanations

test "each suggestion explains itself" {
    busy = [iv(1, "09:00", "14:00"), iv(1, "16:00", "17:00")];
    window = Interval(start=at(1, "09:00"), end=at(7, "00:00"));
    p = plan([task("ps", 60, at(3, "23:59"), "high")], prefs(), busy, {}, window);
    assert p.placements[0].reason == "Free 2pm-4pm Tuesday, due Thursday 11:59pm, high priority", p.placements[0].reason;
}

test "same input always gives the same plan" {
    tasks = [task("a", 90, at(2, "17:00")), task("b", 200, at(4, "12:00"), "high"), task("c", 45, at(2, "17:00"), "low")];
    busy = [iv(0, "10:00", "11:00"), iv(2, "13:00", "15:00")];
    first = [(x.task_id, x.start) for x in plan(tasks, prefs(), busy, {}, week()).placements];
    second = [(x.task_id, x.start) for x in plan(list(reversed(tasks)), prefs(), busy, {}, week()).placements];
    assert first == second;
}

# ------------------------------------------------------------------ work windows (due week + a few days)
# Day numbers past 6 are the following week: at(7, ...) = Mon Oct 26.

def two_weeks -> Interval {
    return Interval(start=at(0, "09:00"), end=at(12, "23:00"));
}

test "work goes in the due week, not the earliest free week" {
    result = plan([task("essay", 120, at(10, "17:00"))], prefs(), [], {}, two_weeks());
    assert hours([Interval(start=p.start, end=p.end) for p in result.placements]) == ["Mon 09:00-11:00"], result.placements;
    assert result.placements[0].start >= at(7, "00:00");
}

test "a Monday deadline can use the few days before it" {
    result = plan([task("quiz prep", 60, at(7, "12:00"))], prefs(), [], {}, two_weeks());
    assert hours([Interval(start=p.start, end=p.end) for p in result.placements]) == ["Fri 09:00-10:00"], result.placements;
}

test "a full due week overflows into the days just before it, nearest first" {
    # Window for a Wed deadline: Sun..Wed = 4 days x 120 min cap = 480 of 600.
    result = plan([task("project", 600, at(9, "17:00"))], prefs(max_focus_minutes_per_day=120), [], {}, two_weeks());
    days = sorted({p.start.astimezone(ZoneInfo(TZ)).date() for p in result.placements});
    assert days[0] == at(5, "00:00").date(), days;                 # Saturday, not Monday of week 1
    assert len(result.unplaced) == 0, result.unplaced;
    early = [p for p in result.placements if p.start < at(6, "00:00")];
    assert len(early) == 1 and "earlier than its due week" in early[0].reason, early;
}

test "tasks whose work window hasn't started are left for later" {
    result = plan([task("later", 60, at(12, "17:00"))], prefs(), [], {}, week());
    assert result.placements == [] and result.unplaced == [], result;
}
