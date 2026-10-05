"""Tests for your own events and clearing suggestions (run: jac test tests/events_api_tests.jac)."""

import os;
import tempfile;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from jaclang.testing.testing { JacTestClient }

glob TZ: str = "America/Detroit";

def _client -> any {
    main_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web", "main.jac");
    return JacTestClient.from_file(main_file, base_path=tempfile.mkdtemp());
}

def _call(client: any, name: str, body: dict = {}) -> any {
    resp = client.post(f"/function/{name}", json=body);
    assert resp.ok, f"{name} failed: {resp.text[:300]}";
    return resp.data["result"];
}

def _day(offset: int) -> str {
    return (datetime.now(ZoneInfo(TZ)) + timedelta(days=offset)).date().isoformat();
}

def _local(iso: str) -> datetime {
    return datetime.fromisoformat(iso).astimezone(ZoneInfo(TZ));
}

def _mine(client: any, start: str = "") -> list[dict] {
    return [e for e in _call(client, "list_events", {"start": start or _day(0), "end": _day(40)}) if e["editable"]];
}

test "a one-off event is busy time for the scheduler" {
    client = _client();
    try {
        client.register_user("ev1", "password123");
        # A task due in 2 days, and nothing else: it gets planned tomorrow at 9.
        _call(client, "create_task", {"title": "Essay", "due": _day(2) + "T21:00", "estimated_minutes": 60});
        plan = _call(client, "suggest_schedule", {"days": 3});
        first = _local(plan["suggestions"][0]["start"]);
        # Put a meeting exactly there; the pending suggestion moves out of its way.
        res = _call(client, "create_event", {
            "title": "Advisor meeting", "day": first.date().isoformat(),
            "start": first.strftime("%H:%M"), "end": (first + timedelta(hours=1)).strftime("%H:%M"),
            "is_class": False
        });
        assert len(res["events"]) == 1 and res["events"][0]["editable"] and res["conflicts"] == [];
        blocks = _call(client, "list_blocks", {"start": "", "days": 14, "status": "suggested"});
        ev = res["events"][0];
        for b in blocks {
            assert not (b["start"] < ev["end"] and ev["start"] < b["end"]), "suggestion still overlaps the meeting";
        }
        assert len(blocks) >= 1;
    } finally {
        client.close();
    }
}

test "overlapping a planned block is reported, not moved" {
    client = _client();
    try {
        client.register_user("ev2", "password123");
        _call(client, "create_task", {"title": "Lab", "due": _day(3) + "T21:00", "estimated_minutes": 60});
        b = _call(client, "suggest_schedule", {"days": 4})["suggestions"][0];
        _call(client, "accept_block", {"id": b["id"]});
        s = _local(b["start"]);
        res = _call(client, "create_event", {
            "title": "Dentist", "day": s.date().isoformat(), "start": s.strftime("%H:%M"),
            "end": (s + timedelta(minutes=30)).strftime("%H:%M"), "is_class": False
        });
        assert len(res["conflicts"]) == 1 and res["conflicts"][0].startswith("Lab"), res["conflicts"];
        kept = _call(client, "list_blocks", {"start": "", "days": 14, "status": "accepted"});
        assert [k["start"] for k in kept] == [b["start"]];          # planned block didn't move
    } finally {
        client.close();
    }
}

test "weekly events, class flag, edit one, delete one or all" {
    client = _client();
    try {
        client.register_user("ev3", "password123");
        res = _call(client, "create_event", {
            "title": "Lab section", "day": _day(1), "start": "14:00", "end": "15:30",
            "is_class": True, "repeat_weeks": 3
        });
        evs = res["events"];
        assert len(evs) == 3 and all(e["is_class"] for e in evs);
        assert [_local(e["start"]).strftime("%H:%M") for e in evs] == ["14:00", "14:00", "14:00"];
        assert (_local(evs[2]["start"]).date() - _local(evs[0]["start"]).date()).days == 14;
        # The class flag survives a refresh (e.g. after another calendar is marked).
        _call(client, "set_series_is_class", {"series_id": "unrelated", "is_class": True});
        assert all(e["is_class"] for e in _mine(client));

        # Move the second week only (the drag/edit path).
        moved = _call(client, "update_event", {"id": evs[1]["id"], "changes": {"start": "16:00", "end": "17:00"}});
        assert _local(moved["events"][0]["start"]).strftime("%H:%M") == "16:00";
        assert sorted([_local(e["start"]).strftime("%H:%M") for e in _mine(client)]) == ["14:00", "14:00", "16:00"];

        assert _call(client, "delete_event", {"id": evs[0]["id"], "whole_series": False}) == 1;
        assert len(_mine(client)) == 2;
        assert _call(client, "delete_event", {"id": evs[1]["id"], "whole_series": True}) == 2;
        assert _mine(client) == [];
    } finally {
        client.close();
    }
}

test "bad input and other people's events are refused" {
    client = _client();
    try {
        client.register_user("ev4", "password123");
        bad = client.post("/function/create_event", json={"title": "x", "day": _day(1), "start": "15:00", "end": "14:00", "is_class": False});
        assert not bad.ok and "end time must be after" in bad.text;
        ev = _call(client, "create_event", {"title": "Mine", "day": _day(1), "start": "10:00", "end": "11:00", "is_class": False})["events"][0];
        client.register_user("ev5", "password123");          # now a different user
        other = client.post("/function/delete_event", json={"id": ev["id"], "whole_series": True});
        assert not other.ok and "can't be found" in other.text;
    } finally {
        client.close();
    }
}

test "sync leaves your events alone; clear removes only suggestions" {
    client = _client();
    try {
        client.register_user("ev6", "password123");
        _call(client, "seed_demo_data");
        _call(client, "create_event", {"title": "Club", "day": _day(1), "start": "18:00", "end": "19:00", "is_class": False});
        _call(client, "sync_calendar");                      # nothing to re-fetch, must not delete
        assert [e["title"] for e in _mine(client)] == ["Club"];

        plan = _call(client, "suggest_schedule", {"days": 7});
        first = plan["suggestions"][0];
        _call(client, "accept_block", {"id": first["id"]});
        removed = _call(client, "clear_suggestions");
        assert removed == len(plan["suggestions"]) - 1, (removed, len(plan["suggestions"]));
        assert _call(client, "list_blocks", {"start": "", "days": 14, "status": "suggested"}) == [];
        assert [b["id"] for b in _call(client, "list_blocks", {"start": "", "days": 14, "status": "accepted"})] == [first["id"]];
    } finally {
        client.close();
    }
}
