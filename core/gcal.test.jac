"""Tests for converting Google Calendar API events (run: jac test core/gcal.jac).

These use sample JSON in the shape Google's events.list returns, so they run
without a Google account or network access.
"""

glob TZ: str = "America/Detroit";

test "timed event in a recurring series" {
    occ = google_event_to_occurrence({
        "id": "abc123_20261020T140000Z",
        "recurringEventId": "abc123",
        "summary": "EECS 376 Lecture",
        "status": "confirmed",
        "start": {"dateTime": "2026-10-20T10:00:00-04:00", "timeZone": "America/Detroit"},
        "end": {"dateTime": "2026-10-20T11:30:00-04:00", "timeZone": "America/Detroit"}
    }, TZ);
    assert occ is not None;
    assert occ.external_id == "abc123_20261020T140000Z";
    assert occ.series_id == "abc123";
    assert occ.start == "2026-10-20T14:00:00+00:00";
    assert occ.end == "2026-10-20T15:30:00+00:00";
    assert not occ.all_day;
}

test "all-day event uses local midnight and exclusive end" {
    occ = google_event_to_occurrence({
        "id": "hol1", "summary": "Fall break",
        "start": {"date": "2026-10-19"}, "end": {"date": "2026-10-21"}
    }, TZ);
    assert occ is not None and occ.all_day;
    assert occ.start == "2026-10-19T04:00:00+00:00";
    assert occ.end == "2026-10-21T04:00:00+00:00";
    assert occ.series_id == "";
}

test "cancelled and 'show as available' events are ignored" {
    base = {"id": "x", "start": {"dateTime": "2026-10-20T10:00:00Z"}, "end": {"dateTime": "2026-10-20T11:00:00Z"}};
    assert google_event_to_occurrence({**base, "status": "cancelled"}, TZ) is None;
    assert google_event_to_occurrence({**base, "transparency": "transparent"}, TZ) is None;
}

test "missing title gets a placeholder" {
    occ = google_event_to_occurrence({
        "id": "y", "start": {"dateTime": "2026-10-20T10:00:00Z"}, "end": {"dateTime": "2026-10-20T11:00:00Z"}
    }, TZ);
    assert occ is not None and occ.title == "(no title)";
}
