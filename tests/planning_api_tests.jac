"""End-to-end tests of planning (run: jac test tests/).

These run against the real clock, so they check properties (no overlaps,
nothing after a deadline, accepted blocks never move) rather than exact times.
Exact-time behavior is covered by core/scheduler.test.jac.
"""

import os;
import tempfile;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from jaclang.testing.testing { JacTestClient }

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

def _call(client: any, name: str, body: dict = {}) -> any {
    resp = client.post(f"/function/{name}", json=body);
    assert resp.ok, f"{name} failed: {resp.text[:300]}";
    return resp.data["result"];
}

def _error(client: any, name: str, body: dict) -> str {
    resp = client.post(f"/function/{name}", json=body);
    assert not resp.ok, f"{name} should have failed";
    return resp.json()["error"]["message"];
}

"""A local due date `days` from now at `hour`, as the API accepts it."""
def _due(days: int, hour: int = 21) -> str {
    d = datetime.now(ZoneInfo(TZ)) + timedelta(days=days);
    return d.strftime("%Y-%m-%d") + f"T{hour:02d}:00";
}

def _t(iso: str) -> datetime {
    return datetime.fromisoformat(iso);
}

def _overlaps(a: dict, b: dict) -> bool {
    return _t(a["start"]) < _t(b["end"]) and _t(b["start"]) < _t(a["end"]);
}

def _setup(client: any, user: str) -> None {
    client.register_user(user, "password123");
    _call(client, "seed_demo_data");
}

test "suggestions respect classes, breaks, deadlines and each other" {
    client = _client();
    try {
        _setup(client, "planner1");
        plan = _call(client, "suggest_schedule", {"days": 7});
        blocks = plan["suggestions"];
        assert len(blocks) > 0;
        events = _call(client, "get_agenda", {"start": "", "days": 14})["events"];
        tasks = {t["id"]: t for t in _call(client, "list_tasks")};
        gap = timedelta(minutes=15);
        for b in blocks {
            for e in events {
                if not e["all_day"] {
                    padded = {"start": (_t(e["start"]) - gap).isoformat(), "end": (_t(e["end"]) + gap).isoformat()};
                    assert not _overlaps(b, padded), f"{b['task_title']} overlaps {e['title']}";
                }
            }
            assert _t(b["end"]) <= _t(tasks[b["task_id"]]["due"]), f"{b['task_title']} is after its deadline";
            local = _t(b["start"]).astimezone(ZoneInfo(TZ));
            assert 9 <= local.hour and _t(b["end"]).astimezone(ZoneInfo(TZ)).hour <= 21;
            assert b["reason"].startswith("Free ");
        }
        for (i, a) in enumerate(blocks) {
            for b in blocks[i + 1:] {
                assert not _overlaps(a, b);
            }
        }
    } finally {
        client.close();
    }
}

test "accepted blocks never move when re-planning" {
    client = _client();
    try {
        _setup(client, "planner2");
        first = _call(client, "suggest_schedule")["suggestions"];
        kept = _call(client, "accept_block", {"id": first[0]["id"]});
        assert kept["status"] == "accepted";

        # Adding a task re-plans the pending suggestions automatically.
        _call(client, "create_task", {"title": "New urgent thing", "due": _due(1), "priority": "high", "estimated_minutes": 60});
        blocks = _call(client, "list_blocks", {"start": "", "days": 14});
        same = [b for b in blocks if b["id"] == kept["id"]][0];
        assert (same["start"], same["end"], same["status"]) == (kept["start"], kept["end"], "accepted");
        assert any(b["task_title"] == "New urgent thing" for b in blocks), "new task was not planned";
        others = [b for b in blocks if b["id"] != kept["id"]];
        assert not any(_overlaps(kept, b) for b in others);
    } finally {
        client.close();
    }
}

test "a rejected slot is not offered again for that task" {
    client = _client();
    try {
        _setup(client, "planner3");
        first = _call(client, "suggest_schedule")["suggestions"][0];
        _call(client, "reject_block", {"id": first["id"]});
        again = _call(client, "suggest_schedule")["suggestions"];
        same_task = [b for b in again if b["task_id"] == first["task_id"]];
        assert not any(_overlaps(first, b) for b in same_task);
    } finally {
        client.close();
    }
}

test "a task that cannot fit is explained" {
    client = _client();
    try {
        _setup(client, "planner4");
        _call(client, "update_preferences", {"changes": {"max_focus_minutes_per_day": 60}});
        _call(client, "create_task", {"title": "Thesis", "due": _due(1), "priority": "high", "estimated_minutes": 600});
        plan = _call(client, "suggest_schedule");
        thesis = [u for u in plan["unscheduled"] if u["title"] == "Thesis"];
        assert thesis, plan["unscheduled"];
        assert thesis[0]["minutes_placed"] < 600;
        assert thesis[0]["reason"], "missing reason";
    } finally {
        client.close();
    }
}

test "adjusting a block checks for clashes and accepts it" {
    client = _client();
    try {
        _setup(client, "planner5");
        block = _call(client, "suggest_schedule")["suggestions"][0];
        # Find a class in the future and try to move the block onto it.
        events = _call(client, "get_agenda", {"start": "", "days": 14})["events"];
        future = [e for e in events if _t(e["start"]) > datetime.now(ZoneInfo("UTC"))];
        clash = future[0];
        local = _t(clash["start"]).astimezone(ZoneInfo(TZ));
        msg = _error(client, "adjust_block", {
            "id": block["id"], "start": local.strftime("%Y-%m-%dT%H:%M"),
            "end": (local + timedelta(minutes=30)).strftime("%Y-%m-%dT%H:%M")
        });
        assert "overlaps" in msg, msg;

        start = (_t(block["start"]) + timedelta(minutes=15)).astimezone(ZoneInfo(TZ));
        moved = _call(client, "adjust_block", {
            "id": block["id"], "start": start.strftime("%Y-%m-%dT%H:%M"),
            "end": (start + timedelta(minutes=30)).strftime("%Y-%m-%dT%H:%M")
        });
        assert moved["status"] == "accepted" and moved["reason"] == "Adjusted by you";
    } finally {
        client.close();
    }
}

test "planned blocks of one task that end up back to back are merged" {
    client = _client();
    try {
        client.register_user("planner_merge", "password123");
        task = _call(client, "create_task", {"title": "Essay", "due": _due(6), "estimated_minutes": 120});
        day = _due(3)[0:10];
        first = _call(client, "suggest_schedule")["suggestions"][0];
        _call(client, "adjust_block", {"id": first["id"], "start": day + "T10:00", "end": day + "T11:00"});
        second = [b for b in _call(client, "suggest_schedule")["suggestions"] if b["task_id"] == task["id"]][0];
        merged = _call(client, "adjust_block", {"id": second["id"], "start": day + "T11:00", "end": day + "T12:00"});
        local = lambda (iso: str) { _t(iso).astimezone(ZoneInfo(TZ)).strftime("%H:%M"); };
        assert (local(merged["start"]), local(merged["end"])) == ("10:00", "12:00"), merged;
        planned = [b for b in _call(client, "list_blocks", {"start": "", "days": 14, "status": "accepted"}) if b["task_id"] == task["id"]];
        assert len(planned) == 1, planned;
    } finally {
        client.close();
    }
}

test "recurring tasks get an instance per occurrence" {
    client = _client();
    try {
        client.register_user("planner6", "password123");
        _call(client, "create_task", {"title": "Gym", "due": _due(0, 21), "estimated_minutes": 45, "recurrence": "DAILY"});
        _call(client, "suggest_schedule", {"days": 7});
        gyms = [t for t in _call(client, "list_tasks") if t["title"] == "Gym"];
        assert 6 <= len(gyms) and len(gyms) <= 8, len(gyms);
        _call(client, "suggest_schedule", {"days": 7});       # no duplicates on re-plan
        assert len([t for t in _call(client, "list_tasks") if t["title"] == "Gym"]) == len(gyms);
        assert "DAILY or WEEKLY" in _error(client, "create_task", {"title": "x", "due": _due(1), "recurrence": "MONTHLY"});
    } finally {
        client.close();
    }
}

test "completing or deleting a task frees its suggestions" {
    client = _client();
    try {
        _setup(client, "planner7");
        blocks = _call(client, "suggest_schedule")["suggestions"];
        target = blocks[0]["task_id"];
        _call(client, "complete_task", {"id": target});
        assert not any(b["task_id"] == target for b in _call(client, "list_blocks", {"start": "", "days": 14}));
        other = [b for b in _call(client, "list_blocks", {"start": "", "days": 14})][0]["task_id"];
        _call(client, "delete_task", {"id": other});
        assert not any(b["task_id"] == other for b in _call(client, "list_blocks", {"start": "", "days": 14}));
    } finally {
        client.close();
    }
}

test "today, agenda and progress views" {
    client = _client();
    try {
        _setup(client, "planner8");
        _call(client, "suggest_schedule");
        _call(client, "accept_all");
        today = _call(client, "get_today");
        assert set(today.keys()) >= {"events", "blocks", "due", "timezone"};
        week = _call(client, "get_agenda", {"start": _demo_monday(), "days": 7});
        assert len(week["events"]) >= 9;
        progress = _call(client, "get_progress");
        assert progress["tasks_open"] == 6;
        # "This week" is Monday-Monday, so compare with the accepted blocks in
        # that same range (on a Sunday night they may all fall next week).
        this_week = _call(client, "list_blocks", {"start": "", "days": 7, "status": "accepted"});
        expected = sum([int((_t(b["end"]) - _t(b["start"])).total_seconds() // 60) for b in this_week]);
        assert progress["minutes_planned"] == expected, (progress["minutes_planned"], expected);
    } finally {
        client.close();
    }
}
