"""The assistant conversation: messages, example prompts, input box.

Used twice with the same logic: full size on /assistant, and docked in the
floating "Ask Morrow" panel (`docked=True`: tighter, scrolls inside the panel).

Every message goes to the server's assistant_chat endpoint (core/assistant.jac),
which may call planner tools; the reply lists what it changed, and
`onChanged` is called so the page on screen can reload its data.
"""

import from "react" { useEffect, useRef }
import from "@jac/runtime" { Link }
import from core.assistant { assistant_chat, assistant_history, assistant_reset, assistant_status }
import type from core.models { ChatMessage }
import from ..lib.ui { error_text }
import from .kit { Button }

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

def _nothing_changed() {}

def:pub AssistantChat(
    docked: bool = False,
    onChanged: Callable[[], None] = _nothing_changed
) -> JsxElement {
    has messages: list[Bubble] = [],
        draft: str = "",
        busy: bool = False,
        error: str = "",
        configured: bool = True,
        model: str = "";
    # A React ref points at the real DOM element (the scrolling message list).
    list_ref: any = useRef(None);

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

    # Keep the newest message in view.
    useEffect(lambda {
        el: any = list_ref.current;
        if el { el.scrollTop = el.scrollHeight; }
    }, [len(messages), busy]);

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
                if len(r.actions) > 0 {
                    onChanged();
                }
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

    async def new_chat(e: MouseEvent) {
        try {
            await assistant_reset();
            messages = [];
            error = "";
        } except Exception as e {
            error = error_text(e);
        }
    }

    <div className={"chat" + (" docked" if docked else "")}>
        <div className="chat-meta">
            <span className="chat-model">{model}</span>
            <span className="spacer"></span>
            <Button label="New chat" small={True} variant="ghost" onClick={new_chat} disabled={busy} />
        </div>
        {(not configured) and <div className="error">The assistant needs a free Gemini key: add GEMINI_API_KEY to .env and restart the server (see README).</div>}

        <div className="chat-log" ref={list_ref} aria-live="polite">
            {if len(messages) == 0 {
                <div>
                    <p className="chat-intro">Ask about your schedule, or have it plan and change things for you. It uses your real calendar and the planner's scheduler, and lists everything it changes. Try:</p>
                    <div className="chat-examples">
                        {for ex in EXAMPLES {
                            <button type="button" key={ex} className="chat-example" onClick={lambda (e: MouseEvent) { send_text(ex); }}>{ex}</button>
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
                            {(not docked) and <li><Link to="/">Open week view</Link></li>}
                        </ul>
                    }}
                </div>
            }}
            {busy and <div className="msg assistant"><div className="bubble muted">Thinking...</div></div>}
        </div>

        {error and <div className="error">{error}</div>}

        <form className="chat-form" onSubmit={send}>
            <input id="chat-input" className="chat-input" aria-label="Message the assistant"
                autoFocus={docked}
                placeholder={"Ask Morrow…" if docked else "e.g. Fit 3 hours of studying for my midterm before Thursday"}
                value={draft} onChange={lambda (e: ChangeEvent) { draft = e.target.value; }} disabled={busy} />
            <Button id="send" label="Send" variant="primary" submit={True} disabled={busy or not draft.strip()} />
        </form>
    </div>
}
