"""Canvas feed parsing tests (run: jac test core/canvas.jac).

The sample follows the shape of a real Canvas calendar feed: assignments have
UIDs starting with "event-assignment-" and the course in brackets.
"""

import from zoneinfo { ZoneInfo }

glob TZ: str = "America/Detroit";

def sample -> str {
    return "\r\n".join([
        "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Instructure//Canvas//EN",
        "X-WR-CALNAME:Jonathan Calendar (Canvas)",
        "BEGIN:VEVENT",
        "UID:event-assignment-1001",
        "DTSTART:20261006T035900Z", "DTEND:20261006T035900Z",
        "SUMMARY:Assignment 7: Scope (in class) [EECS 449 001 FA 2026]",
        "URL;VALUE=URI:https://umich.instructure.com/courses/1/assignments/1001",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "UID:event-assignment-1002",
        "DTSTART;VALUE=DATE:20261008", "DTEND;VALUE=DATE:20261008",
        "SUMMARY:Unit 1 Reflection [PSYCH 111 002 FA 2026]",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "UID:event-calendar-event-55",
        "DTSTART:20261007T130000Z", "DTEND:20261007T143000Z",
        "SUMMARY:Discussion section [EECS 449 001 FA 2026]",
        "END:VEVENT",
        "BEGIN:VEVENT",
        "UID:event-quiz-77",
        "DTSTART:20261009T120000Z",
        "SUMMARY:Quiz 3",
        "URL;VALUE=URI:https://umich.instructure.com/courses/2/quizzes/77",
        "END:VEVENT",
        "END:VCALENDAR"
    ]) + "\r\n";
}

test "only assignments are read, soonest first" {
    items = parse_canvas_feed(sample(), TZ);
    assert [a.uid for a in items] == ["event-assignment-1001", "event-assignment-1002", "event-quiz-77"];
}

test "course is split from the title and shortened" {
    a = parse_canvas_feed(sample(), TZ)[0];
    assert a.title == "Assignment 7: Scope (in class)";
    assert a.course == "EECS 449";
    assert a.url.endswith("/assignments/1001");
}

test "due time is kept exactly (11:59pm local)" {
    a = parse_canvas_feed(sample(), TZ)[0];
    local = a.due.astimezone(ZoneInfo(TZ));
    assert (local.month, local.day, local.hour, local.minute) == (10, 5, 23, 59);
}

test "an all-day due date means end of that day" {
    a = parse_canvas_feed(sample(), TZ)[1];
    local = a.due.astimezone(ZoneInfo(TZ));
    assert (local.day, local.hour, local.minute) == (8, 23, 59);
}

test "titles without a course still work" {
    assert split_course("Quiz 3") == ("Quiz 3", "");
    assert split_course("Lab [CHEM 210]") == ("Lab", "CHEM 210");
    assert split_course("Paper [Writing Seminar]") == ("Paper", "Writing Seminar");
}
