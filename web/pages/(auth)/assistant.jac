"""/assistant - chat with the AI planning assistant.

Every message goes to the server's assistant_chat endpoint (core/assistant.jac),
which may call planner tools; the reply lists what it changed.
"""

import from "@jac/runtime" { Link }
import from core.assistant { assistant_chat, assistant_history, assistant_reset, assistant_status }
import type from core.models { ChatMessage }
import from ...lib.ui { error_text }

glob EXAMPLES: list[str] = [
    "What's on my plate this week?",
    "Plan my week and explain the suggestions",
    "Add a 2-hour PSYCH paper due Friday 5pm, high priority",
    "I don't want to work after 8pm",
    "When am I free on Thursday afternoon?"
];

"""One chat bubble (browser-side; server types can't be built in the browser)."""
obj Bubble {
    has role: str, text: str, actions: list[str] = [];
}

def to_bubble(m: ChatMessage) -> Bubble {
    return Bubble(role=m.role, text=m.text, actions=m.actions);
}

def:pub AssistantPage() -> JsxPage {
    has messages: list[Bubble] = [],
        draft: str = "",
        busy: bool = False,
        error: str = "",
        configured: bool = True,
        model: str = "";

    async can with entry {
        try {
            s = await assistant_status();
            configured = s.configured;
            model = s.model;
            messages = [to_bubble(m) for m in await assistant_history()];
        } except Exception as e {
            error = error_text(e);
        }
    }

    async def send_text(text: str) {
        text = text.strip();
        if not text or busy {
            return;
        }
        error = "";
        draft = "";
        # Show the user's message right away, then the reply when it arrives.
        messages = messages + [Bubble(role="user", text=text, actions=[])];
        busy = True;
        try {
            r = await assistant_chat(text);
            if r.error {
                error = r.error;
            } else {
                messages = messages + [Bubble(role="assistant", text=r.reply, actions=r.actions)];
            }
        } except Exception as e {
            error = error_text(e);
        }
        busy = False;
    }

    async def send(e: FormEvent) {
        e.preventDefault();
        await send_text(draft);
    }

    async def new_chat {
        try {
            await assistant_reset();
            messages = [];
            error = "";
        } except Exception as e {
            error = error_text(e);
        }
    }

    <div style={{"maxWidth": "780px", "margin": "0 auto"}}>
        <div className="row" style={{"marginBottom": "8px"}}>
            <h1 style={{"fontSize": "20px", "margin": "0"}}>Planning assistant</h1>
            <span className="spacer"></span>
            <span className="muted" style={{"fontSize": "12px"}}>{model}</span>
            <button className="btn small" onClick={new_chat} disabled={busy}>New chat</button>
        </div>
        {(not configured) and <div className="error">The assistant needs a free Gemini key: add GEMINI_API_KEY to .env and restart the server (see README).</div>}

        <div className="panel" style={{"minHeight": "320px"}}>
            {if len(messages) == 0 {
                <div>
                    <p className="muted">Ask about your schedule, or have it plan and change things for you. It uses your real calendar and the planner's scheduler, and lists everything it changes. Try:</p>
                    <div className="row">
                        {for ex in EXAMPLES {
                            <button key={ex} className="btn small" onClick={lambda (e: MouseEvent) { send_text(ex); }}>{ex}</button>
                        }}
                    </div>
                </div>
            }}
            {for (i, m) in enumerate(messages) {
                <div key={str(i)} className={"msg " + m.role}>
                    <div className="bubble">{m.text}</div>
                    {if len(m.actions) > 0 {
                        <ul className="actions">
                            {for a in m.actions { <li key={a}>✓ {a}</li> }}
                            <li><Link to="/">Open week view</Link></li>
                        </ul>
                    }}
                </div>
            }}
            {busy and <div className="msg assistant"><div className="bubble muted">Thinking...</div></div>}
        </div>

        {error and <div className="error">{error}</div>}

        <form className="row" onSubmit={send}>
            <input id="chat-input" style={{"flex": "1", "padding": "10px 12px", "border": "1px solid #e3e6eb", "borderRadius": "8px"}}
                placeholder="e.g. Fit 3 hours of studying for my midterm before Thursday"
                value={draft} onChange={lambda (e: ChangeEvent) { draft = e.target.value; }} disabled={busy} />
            <button id="send" className="btn primary" type="submit" disabled={busy or not draft.strip()}>Send</button>
        </form>
    </div>
}
