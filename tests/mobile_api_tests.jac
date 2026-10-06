"""End-to-end tests of the phone app's walkers (core/mobile_api.jac), the
API the mobile app calls (run: jac test tests/).

The test client is built from the service's own entry file, so each walker
is POSTed to /walker/<Name> as the logged-in user; its results come back in
`reports`. The walkers call the same core functions the web app does, which
tests/*_api_tests.jac cover in depth; these check the phone's wiring.
"""

import os;
import tempfile;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from jaclang.testing.testing { JacTestClient }

glob TZ: str = "America/Detroit";

def _client -> any {
    service_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "core", "mobile_api.jac");
    return JacTestClient.from_file(service_file, base_path=tempfile.mkdtemp());
}

"""Spawn walker `name` with `fields`; returns its reports."""
def _walk(client: any, name: str, fields: dict = {}) -> list {
    resp = client.post(f"/walker/{name}", json=fields);
    assert resp.ok, f"{name} failed: {resp.text[:300]}";
    return resp.data["reports"];
}

"""A local date `days` from today, YYYY-MM-DD."""
def _day(days: int) -> str {
    return (datetime.now(ZoneInfo(TZ)) + timedelta(days=days)).strftime("%Y-%m-%d");
}

def _new_task(client: any, title: str, days: int, minutes: int = 60) -> dict {
    return _walk(client, "SaveTask", {
        "task_id": "", "title": title, "due": _day(days) + "T17:00", "priority": "medium",
        "estimated_minutes": minutes, "category": "TEST 101", "notes": "", "recurrence": ""
    })[0];
}

test "week, tasks and coming up for the Plan screen" {
    client = _client();
    try {
        client.register_user("phone1", "password123");
        _walk(client, "LoadDemo");
        week = _walk(client, "WeekScreen", {"start": ""})[0];
        assert len(week["days"]) == 7, week;
        open_tasks = _walk(client, "TaskList", {"show_all": False})[0];
        assert len(open_tasks) > 0;
        coming = _walk(client, "ComingUpData", {"start": "", "limit": 5})[0];
        assert coming["open_count"] == len(open_tasks), (coming["open_count"], len(open_tasks));
        assert len(coming["items"]) <= 5;
    } finally {
        client.close();
    }
}

test "add, edit, finish, reopen and delete a task" {
    client = _client();
    try {
        client.register_user("phone2", "password123");
        t = _new_task(client, "Essay", 5);
        assert t["title"] == "Essay" and t["category"] == "TEST 101", t;
        edited = _walk(client, "SaveTask", {
            "task_id": t["id"], "title": "Essay draft", "due": _day(6) + "T09:00", "priority": "high",
            "estimated_minutes": 90, "category": "TEST 101", "notes": "outline first", "recurrence": ""
        })[0];
        assert edited["title"] == "Essay draft" and edited["priority"] == "high" and edited["estimated_minutes"] == 90;
        assert _walk(client, "FinishTask", {"task_id": t["id"]})[0]["status"] == "done";
        assert _walk(client, "TaskList", {"show_all": False})[0] == [];
        assert _walk(client, "ReopenTask", {"task_id": t["id"]})[0]["status"] == "todo";
        assert _walk(client, "TaskDetail", {"task_id": t["id"]})[0]["notes"] == "outline first";
        assert _walk(client, "RemoveTask", {"task_id": t["id"]})[0] == True;
        assert _walk(client, "TaskList", {"show_all": True})[0] == [];
    } finally {
        client.close();
    }
}

test "plan, change a block's time, accept all and clear" {
    client = _client();
    try {
        client.register_user("phone3", "password123");
        t = _new_task(client, "Lab report", 4, 60);
        other = _new_task(client, "Reading", 5, 30);
        plan = _walk(client, "PlanAhead", {"days": 21})[0];
        mine = [b for b in plan["suggestions"] if b["task_id"] == t["id"]];
        assert len(mine) == 1, plan;
        day = _day(2);
        moved = _walk(client, "MoveBlock", {"block_id": mine[0]["id"], "day": day, "start": "10:00", "end": "11:00"})[0];
        local = datetime.fromisoformat(moved["start"]).astimezone(ZoneInfo(TZ));
        assert moved["status"] == "accepted" and local.strftime("%Y-%m-%d %H:%M") == day + " 10:00", moved;
        # Fully planned now, so reopening after finishing shows it as planned again.
        _walk(client, "FinishTask", {"task_id": t["id"]});
        assert _walk(client, "ReopenTask", {"task_id": t["id"]})[0]["status"] == "scheduled";

        _walk(client, "PlanAhead", {"days": 21});
        assert _walk(client, "ClearSuggestions")[0] >= 1;
        _walk(client, "PlanAhead", {"days": 21});
        accepted = _walk(client, "AcceptAllBlocks")[0];
        assert any(b["task_id"] == other["id"] for b in accepted), accepted;
        assert _walk(client, "WeekScreen", {"start": ""})[0]["suggested_count"] == 0;
    } finally {
        client.close();
    }
}

test "add and delete events, and save preferences" {
    client = _client();
    try {
        client.register_user("phone4", "password123");
        r = _walk(client, "SaveEvent", {
            "event_id": "", "title": "Advisor meeting", "day": _day(1), "start": "15:00", "end": "16:00",
            "weeks": 3, "is_class": False
        })[0];
        assert len(r["events"]) == 3, r;
        changed = _walk(client, "SaveEvent", {
            "event_id": r["events"][0]["id"], "title": "Advisor meeting", "day": _day(1),
            "start": "15:30", "end": "16:30", "weeks": 1, "is_class": False
        })[0];
        assert len(changed["events"]) == 1;
        assert _walk(client, "RemoveEvent", {"event_id": r["events"][0]["id"], "whole_series": True})[0] == 3;

        p = _walk(client, "SavePrefs", {"changes": {"city": "Ann Arbor", "work_end": "20:00", "days_off": ["sat"]}})[0];
        assert p["city"] == "Ann Arbor" and p["work_end"] == "20:00" and p["days_off"] == ["sat"], p;
        assert _walk(client, "Prefs")[0]["work_end"] == "20:00";
        assert _walk(client, "CanvasFeed")[0] == "";
    } finally {
        client.close();
    }
}
