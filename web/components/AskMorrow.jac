"""Floating assistant launcher, bottom right of every signed-in page: a white
"Ask Morrow" pill and Morrow's round avatar. Either one opens the assistant
docked above them; ✕ or Esc closes it.

When the assistant changes the plan, a `morrow:changed` browser event is sent
so the page underneath (e.g. the Planner) can reload what it shows.
"""

import from "react" { useEffect }
import from .kit { IconButton }
import from .MorrowFace { MorrowFace }
import from .AssistantChat { AssistantChat }

def plan_changed {
    window.dispatchEvent(new(CustomEvent, "morrow:changed"));  # jac:ignore[E1053,E1032]
}

def:pub AskMorrow() -> JsxElement {
    has open: bool = False;

    # Esc closes the panel (listener only while it's open).
    useEffect(lambda {
        if not open {
            return;                # no cleanup (React wants undefined, not None/null)
        }
        def on_key(e: any) {
            if e.key == "Escape" { open = False; }
        }
        window.addEventListener("keydown", on_key);
        return lambda { window.removeEventListener("keydown", on_key); };
    }, [open]);

    def toggle(e: MouseEvent) {
        open = not open;
    }

    <div className="ask-morrow">
        {if open {
            <section className="ask-panel" role="dialog" aria-label="Ask Morrow">
                <header className="ask-panel-head">
                    <MorrowFace size="sm" />
                    <span className="ask-panel-title">Ask Morrow</span>
                    <span className="spacer"></span>
                    <IconButton icon="x" label="Close assistant" onClick={toggle} />
                </header>
                <AssistantChat docked={True} onChanged={plan_changed} />
            </section>
        }}
        <div className="ask-launcher">
            <button type="button" className="ask-pill" onClick={toggle} aria-expanded={open}>Ask Morrow</button>
            <button type="button" className="ask-avatar" onClick={toggle} aria-expanded={open}
                aria-label={"Close assistant" if open else "Open assistant"}>
                <MorrowFace />
            </button>
        </div>
    </div>
}
