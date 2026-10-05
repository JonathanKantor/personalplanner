"""End-to-end tests of Canvas feed import (run: jac test tests/canvas_api_tests.jac).

A tiny local HTTP server stands in for Canvas, serving a feed whose due dates
are relative to today. Changing the served text simulates Canvas changing.
"""

import os;
import tempfile;
import threading;
import from http.server { HTTPServer, SimpleHTTPRequestHandler }
import from functools { partial }
import from datetime { datetime, timedelta, timezone }
import from jaclang.testing.testing { JacTestClient }

def _client -> any {
    main_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web", "main.jac");
    return JacTestClient.from_file(main_file, base_path=tempfile.mkdtemp());
}

def _call(client: any, name: str, body: dict = {}) -> any {
    resp = client.post(f"/function/{name}", json=body);
    assert resp.ok, f"{name} failed: {resp.text[:300]}";
    return resp.data["result"];
}

def _stamp(days: int) -> str {
    return (datetime.now(timezone.utc) + timedelta(days=days)).strftime("%Y%m%dT035900Z");
}

def _event(uid: str, days: int, summary: str) -> list[str] {
    return ["BEGIN:VEVENT", f"UID:{uid}", f"DTSTART:{_stamp(days)}", f"DTEND:{_stamp(days)}",
            f"SUMMARY:{summary}", "END:VEVENT"];
}

def _feed(events: list[list[str]]) -> str {
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Instructure//Canvas//EN"];
    for e in events {
        lines += e;
    }
    return "\r\n".join(lines + ["END:VCALENDAR"]) + "\r\n";
}

"""Serve `folder` over HTTP on a free port; returns (server, base URL)."""
def _serve(folder: str) -> tuple[any, str] {
    handler = partial(SimpleHTTPRequestHandler, directory=folder);
    server = HTTPServer(("127.0.0.1", 0), handler);
    threading.Thread(target=server.serve_forever, daemon=True).start();
    return (server, f"http://127.0.0.1:{server.server_address[1]}");
}

test "sync, import with estimates, re-sync updates without duplicates" {
    folder = tempfile.mkdtemp();
    path = os.path.join(folder, "feed.ics");
    with open(path, "w") as f {
        f.write(_feed([
            _event("event-assignment-1", 2, "Problem set 5 [EECS 376 001 FA 2026]"),
            _event("event-assignment-2", 4, "Essay draft [ENGLISH 125 004 FA 2026]"),
            _event("event-assignment-3", -3, "Old quiz [EECS 376 001 FA 2026]"),
            _event("event-calendar-event-9", 1, "Section meeting [EECS 376 001 FA 2026]")
        ]));
    }
    (server, base) = _serve(folder);
    client = _client();
    try {
        client.register_user("canvas1", "password123");

        # 1. Sync: assignments listed with statuses; the meeting is ignored.
        preview = _call(client, "canvas_sync", {"url": f"{base}/feed.ics"});
        status = {i["title"]: i["status"] for i in preview["items"]};
        assert status == {"Problem set 5": "new", "Essay draft": "new", "Old quiz": "past_due"}, status;
        assert preview["courses"] == ["ENGLISH 125", "EECS 376"] or preview["courses"] == ["EECS 376", "ENGLISH 125"];
        assert _call(client, "canvas_feed_url") == f"{base}/feed.ics";

        # 2. Import one with my estimate, dismiss the other.
        result = _call(client, "canvas_import", {"choices": [
            {"uid": "event-assignment-1", "include": True, "estimated_minutes": 150, "priority": "high"},
            {"uid": "event-assignment-2", "include": False}
        ]});
        assert (result["created"], result["dismissed"]) == (1, 1), result;
        tasks = _call(client, "list_tasks");
        assert [(t["title"], t["estimated_minutes"], t["priority"], t["category"]) for t in tasks] == [("Problem set 5", 150, "high", "EECS 376")];

        # 3. Canvas moves the deadline and renames it: re-sync updates the task,
        #    keeps my estimate, and still remembers the dismissed one.
        with open(path, "w") as f {
            f.write(_feed([
                _event("event-assignment-1", 5, "Problem set 5 (revised) [EECS 376 001 FA 2026]"),
                _event("event-assignment-2", 4, "Essay draft [ENGLISH 125 004 FA 2026]"),
                _event("event-assignment-4", 6, "Reading response [ENGLISH 125 004 FA 2026]")
            ]));
        }
        again = _call(client, "canvas_sync", {"url": ""});
        assert again["updated"] == 1;
        status = {i["title"]: i["status"] for i in again["items"]};
        assert status == {"Problem set 5 (revised)": "imported", "Essay draft": "dismissed", "Reading response": "new"}, status;
        tasks = _call(client, "list_tasks");
        assert len(tasks) == 1 and tasks[0]["title"] == "Problem set 5 (revised)" and tasks[0]["estimated_minutes"] == 150;

        # 4. Importing the same assignment again is skipped, not duplicated.
        again = _call(client, "canvas_import", {"choices": [{"uid": "event-assignment-1", "include": True, "estimated_minutes": 30}]});
        assert again["skipped"] == 1 and again["created"] == 0;
        assert len(_call(client, "list_tasks")) == 1;
    } finally {
        client.close();
        server.shutdown();
    }
}

test "bad input is explained" {
    folder = tempfile.mkdtemp();
    with open(os.path.join(folder, "plain.ics"), "w") as f {
        f.write(_feed([_event("not-canvas-1", 2, "Dentist")]));
    }
    (server, base) = _serve(folder);
    client = _client();
    try {
        client.register_user("canvas2", "password123");
        resp = client.post("/function/canvas_sync", json={"url": ""});
        assert not resp.ok and "Canvas calendar feed URL" in resp.text;
        resp = client.post("/function/canvas_sync", json={"url": f"{base}/plain.ics"});
        assert not resp.ok and "No assignments found" in resp.text, resp.text[:200];
    } finally {
        client.close();
        server.shutdown();
    }
}
