"""Tests for the AI assistant (run: jac test tests/assistant_api_tests.jac).

No API key or network: the model is replaced by byLLM's MockLLM, whose
scripted outputs say which tools the "model" calls (MockToolCall) and what it
finally answers. The tools themselves run for real against the planner, so
these tests check the real effects (tasks created, schedule planned, ...).
"""

import os;
import tempfile;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from jaclang.testing.testing { JacTestClient }
import from jaclang.byllm.lib { MockLLM, MockToolCall, MockError }
import core.assistant as assistant;

def _client -> any {
    main_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "web", "main.jac");
    return JacTestClient.from_file(main_file, base_path=tempfile.mkdtemp());
}

def _call(client: any, name: str, body: dict = {}) -> any {
    resp = client.post(f"/function/{name}", json=body);
    assert resp.ok, f"{name} failed: {resp.text[:300]}";
    return resp.data["result"];
}

"""Script the model's behaviour for the next chat message(s)."""
def _mock(outputs: list) -> any {
    m = MockLLM(model_name="mockllm", config={"outputs": outputs});
    assistant.llm = m;
    return m;
}

def _due(days: int) -> str {
    return (datetime.now(ZoneInfo("America/Detroit")) + timedelta(days=days)).strftime("%Y-%m-%d") + "T17:00";
}

test "the assistant acts through planner tools" {
    client = _client();
    try {
        client.register_user("asst1", "password123");
        _mock([
            MockToolCall(tool=assistant.tool_add_task, args={
                "title": "Problem set 6", "due": _due(4), "estimated_minutes": 120,
                "priority": "high", "course": "EECS 376"
            }),
            MockToolCall(tool=assistant.tool_plan, args={"days": 7}),
            "Added Problem set 6 and planned your week: 2 sessions before Friday."
        ]);
        r = _call(client, "assistant_chat", {"message": "Add PS6 due Friday, 2 hours, high priority, then plan my week"});
        assert r["error"] == "", r["error"];
        assert r["reply"].startswith("Added Problem set 6");
        assert len(r["actions"]) == 2, r["actions"];
        assert r["actions"][0].startswith("Added task \"Problem set 6\"");
        assert r["actions"][1].startswith("Planned the next 7 day(s)");
        tasks = _call(client, "list_tasks");
        assert [(t["title"], t["estimated_minutes"], t["category"]) for t in tasks] == [("Problem set 6", 120, "EECS 376")];
        blocks = _call(client, "list_blocks", {"start": "", "days": 14, "status": "suggested"});
        assert sum([1 for b in blocks if b["task_title"] == "Problem set 6"]) >= 1;
    } finally {
        client.close();
    }
}

test "conversation is remembered and can be reset" {
    client = _client();
    try {
        client.register_user("asst2", "password123");
        _mock(["Hi! What should we plan?"]);
        _call(client, "assistant_chat", {"message": "hello, I have a busy week"});
        m = _mock(["Sure, let's look at Thursday."]);
        _call(client, "assistant_chat", {"message": "what about thursday?"});
        # The second model call saw the first exchange.
        assert "busy week" in str(m.seen_prompts[0]), m.seen_prompts[0][:500];
        history = _call(client, "assistant_history");
        assert [h["role"] for h in history] == ["user", "assistant", "user", "assistant"];
        assert history[3]["text"] == "Sure, let's look at Thursday.";
        assert _call(client, "assistant_reset") == True;
        assert _call(client, "assistant_history") == [];
    } finally {
        client.close();
    }
}

test "a tool error is reported to the model, not to the user" {
    client = _client();
    try {
        client.register_user("asst3", "password123");
        _mock([
            MockToolCall(tool=assistant.tool_complete_task, args={"task_id": "no-such-task"}),
            "I couldn't find that task. Which one did you mean?"
        ]);
        r = _call(client, "assistant_chat", {"message": "mark my essay done"});
        assert r["error"] == "" and r["actions"] == [];
        assert "couldn't find" in r["reply"];
    } finally {
        client.close();
    }
}

test "model problems become readable messages" {
    client = _client();
    try {
        client.register_user("asst4", "password123");
        _mock([MockError(error=Exception("AuthenticationError: API key not valid"))]);
        r = _call(client, "assistant_chat", {"message": "plan my week"});
        assert "GEMINI_API_KEY" in r["error"], r["error"];
        _mock([MockError(error=Exception("429 RESOURCE_EXHAUSTED quota exceeded"))]);
        r = _call(client, "assistant_chat", {"message": "plan my week"});
        assert "quota" in r["error"], r["error"];
        _mock([MockError(error=Exception("503 UNAVAILABLE: This model is currently experiencing high demand"))]);
        r = _call(client, "assistant_chat", {"message": "plan my week"});
        assert "busy" in r["error"], r["error"];
    } finally {
        client.close();
    }
}

test "chat requires login and a message" {
    client = _client();
    try {
        assert client.post("/function/assistant_chat", json={"message": "hi"}).status_code == 401;
        client.register_user("asst5", "password123");
        resp = client.post("/function/assistant_chat", json={"message": "   "});
        assert not resp.ok and "Type a message" in resp.text;
    } finally {
        client.close();
    }
}

test "the assistant can add a meeting and clear suggestions" {
    client = _client();
    try {
        client.register_user("asst6", "password123");
        _call(client, "seed_demo_data");
        _call(client, "suggest_schedule", {"days": 7});
        tomorrow = (datetime.now(ZoneInfo("America/Detroit")) + timedelta(days=1)).strftime("%Y-%m-%d");
        _mock([
            MockToolCall(tool=assistant.tool_add_event, args={
                "title": "Advisor meeting", "date": tomorrow, "start": "15:00", "end": "16:00", "repeat_weeks": 1
            }),
            MockToolCall(tool=assistant.tool_clear_suggestions, args={}),
            "Added the meeting and cleared the suggestions."
        ]);
        r = _call(client, "assistant_chat", {"message": "I have an advisor meeting tomorrow 3-4pm. Also clear the suggestions."});
        assert r["error"] == "", r["error"];
        assert r["actions"][0].startswith("Added event \"Advisor meeting\""), r["actions"];
        assert r["actions"][1].startswith("Cleared"), r["actions"];
        mine = [e for e in _call(client, "list_events", {"start": tomorrow, "end": ""}) if e["editable"]];
        assert [e["title"] for e in mine] == ["Advisor meeting"];
        assert _call(client, "list_blocks", {"start": "", "days": 14, "status": "suggested"}) == [];
    } finally {
        client.close();
    }
}
