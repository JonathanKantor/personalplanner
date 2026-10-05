"""End-to-end tests of the calendar endpoints (run: jac test tests/).

JacTestClient runs the real server in-process (no port) against a throwaway
database folder, so these exercise auth, persistence, and the HTTP layer.
"""

import os;
import tempfile;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from jaclang.testing.testing { JacTestClient }
import from core.seed { demo_ics, DemoWeekly }
import from core.timeutil { now_utc, week_start, zone }

glob TZ: str = "America/Detroit";

"""Monday (local date) of the week the demo seed fills: this week, or next
week when run on a weekend (same rule as core/seed.jac)."""
def _demo_monday -> str {
    d = datetime.now(ZoneInfo(TZ)) + timedelta(days=2);
    return (d.date() - timedelta(days=d.weekday())).isoformat();
}

def _client -> any {
    main_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web", "main.jac");
    return JacTestClient.from_file(main_file, base_path=tempfile.mkdtemp());
}

"""POST /function/<name>; returns the function's return value."""
def _call(client: any, name: str, body: dict = {}) -> any {
    resp = client.post(f"/function/{name}", json=body);
    assert resp.ok, f"{name} failed: {resp.text[:300]}";
    return resp.data["result"];
}

def _ics(events: list[DemoWeekly]) -> str {
    monday = week_start(now_utc(), TZ).astimezone(zone(TZ));
    return demo_ics("Fall classes", events, TZ, monday);
}

glob MWF: DemoWeekly = DemoWeekly(uid="c1", title="Algorithms", days=[0, 2, 4], start="10:00", end="11:00"),
     TTH: DemoWeekly = DemoWeekly(uid="c2", title="Databases", days=[1, 3], start="14:00", end="15:30");

test "re-importing updates instead of duplicating" {
    client = _client();
    try {
        client.register_user("resync", "password123");
        first = _call(client, "import_ics", {"content": _ics([MWF, TTH]), "name": "Fall"});
        assert first["added"] > 0 and first["updated"] == 0 and first["removed"] == 0;
        total = first["total"];

        # Same file again: nothing changes.
        again = _call(client, "import_ics", {"content": _ics([MWF, TTH]), "name": "Fall"});
        assert again["added"] == 0 and again["updated"] == 0 and again["total"] == total;

        # Rename one course and drop the other: titles update, dropped events go.
        renamed = DemoWeekly(uid="c1", title="Algorithms (EECS 376)", days=[0, 2, 4], start="10:00", end="11:00");
        third = _call(client, "import_ics", {"content": _ics([renamed]), "name": "Fall"});
        assert third["added"] == 0;
        assert third["updated"] > 0;
        assert third["removed"] > 0;
        assert len(_call(client, "list_calendars")) == 1;   # still one calendar
        titles = {e["title"] for e in _call(client, "list_events")};
        assert titles == {"Algorithms (EECS 376)"}, titles;
    } finally {
        client.close();
    }
}

test "marking a series or calendar as class" {
    client = _client();
    try {
        client.register_user("classes", "password123");
        _call(client, "import_ics", {"content": _ics([MWF, TTH]), "name": "Fall"});
        assert not any(e["is_class"] for e in _call(client, "list_events"));

        series = _call(client, "list_series");
        assert {s["title"] for s in series} == {"Algorithms", "Databases"};
        algo = [s for s in series if s["title"] == "Algorithms"][0];
        _call(client, "set_series_is_class", {"series_id": algo["series_id"], "is_class": True});
        events = _call(client, "list_events");
        assert all(e["is_class"] == (e["title"] == "Algorithms") for e in events);

        # Re-sync must keep the flag.
        _call(client, "import_ics", {"content": _ics([MWF, TTH]), "name": "Fall"});
        events = _call(client, "list_events");
        assert all(e["is_class"] == (e["title"] == "Algorithms") for e in events);

        cal = _call(client, "list_calendars")[0];
        _call(client, "set_calendar_is_class", {"calendar_id": cal["id"], "is_class": True});
        assert all(e["is_class"] for e in _call(client, "list_events"));
    } finally {
        client.close();
    }
}

test "calendars are private to each user" {
    client = _client();
    try {
        client.register_user("alice_cal", "password123");
        _call(client, "import_ics", {"content": _ics([MWF]), "name": "Mine"});
        client.register_user("bob_cal", "password123");      # now acting as bob
        assert _call(client, "list_calendars") == [];
        assert _call(client, "list_events") == [];
    } finally {
        client.close();
    }
}

test "demo seed creates classes and is repeatable" {
    client = _client();
    try {
        client.register_user("demo", "password123");
        first = _call(client, "seed_demo_data");
        second = _call(client, "seed_demo_data");
        assert first["calendars"] == second["calendars"];        # no duplicates
        cals = _call(client, "list_calendars");
        assert {c["name"] for c in cals} == {"Demo: Classes", "Demo: Personal"};
        events = _call(client, "list_events", {"start": _demo_monday(), "end": ""});
        classes = [e for e in events if e["is_class"]];
        assert len(classes) == 9, len(classes);                   # 9 class meetings per demo week
        assert {e["title"] for e in events if not e["is_class"]} == {"Robotics club", "Dentist"};
    } finally {
        client.close();
    }
}

test "anonymous callers are rejected" {
    client = _client();
    try {
        resp = client.post("/function/list_calendars", json={});
        assert resp.status_code == 401;
    } finally {
        client.close();
    }
}
