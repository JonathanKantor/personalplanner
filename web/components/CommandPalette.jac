"""Cmd/Ctrl+K command palette: type to filter, ↑/↓ to choose, Enter to run,
Esc to close.

Commands either navigate, open the floating assistant (`morrow:ask` browser
event), or run a Planner action (`morrow:command` event with the action's
name; the Planner page listens). Planner actions are only listed on the
Planner, where something is listening.
"""

import from "@jac/runtime" { useNavigate }
import from .kit { Icon }

"""One palette entry. kind: "go" (to = path) | "planner" | "ask"."""
obj Command {
    has id: str, label: str, icon: str, kind: str, to: str = "", keys: str = "";
}

glob GO: list[Command] = [
    Command(id="go-planner", label="Go to Planner", icon="calendar", kind="go", to="/"),
    Command(id="go-tasks", label="Go to Tasks", icon="tasks", kind="go", to="/tasks"),
    Command(id="go-assistant", label="Open assistant page", icon="chat", kind="go", to="/assistant"),
    Command(id="go-canvas", label="Import from Canvas", icon="book", kind="go", to="/canvas"),
    Command(id="go-settings", label="Settings", icon="settings", kind="go", to="/settings")
];

glob PLANNER: list[Command] = [
    Command(id="new-event", label="Add event", icon="plus", kind="planner", keys="N"),
    Command(id="new-task", label="Add task", icon="plus", kind="planner", keys="A"),
    Command(id="suggest", label="Suggest schedule", icon="sparkles", kind="planner"),
    Command(id="today", label="Go to this week", icon="calendar", kind="planner", keys="T"),
    Command(id="prev", label="Previous week", icon="chevron-left", kind="planner", keys="← / K"),
    Command(id="next", label="Next week", icon="chevron-right", kind="planner", keys="→ / J"),
    Command(id="view-week", label="Week view", icon="grid", kind="planner"),
    Command(id="view-agenda", label="Agenda view", icon="list", kind="planner")
];

glob ASK: Command = Command(id="ask", label="Ask Morrow", icon="sparkles", kind="ask");

def send_event(name: str, detail: str = "") {
    window.dispatchEvent(new(CustomEvent, name, {"detail": detail}));  # jac:ignore[E1053,E1032]
}

def:pub CommandPalette(path: str, onClose: Callable[[], None]) -> JsxElement {
    has query: str = "",
        index: int = 0;                       # highlighted row
    nav = useNavigate();

    all_commands = (PLANNER if path == "/" else []) + [ASK] + GO;
    q = query.strip().lower();
    """Best matches first: label starts with the query, then a word in it
    does ("ask" -> "Ask Morrow" before "Add task"), then anywhere."""
    def rank(c: Command) -> int {
        label = c.label.lower();
        if label.startswith(q) { return 0; }
        if (" " + q) in (" " + label) { return 1; }
        return 2;
    }
    shown = sorted([c for c in all_commands if q in c.label.lower()], key=rank);
    current = min(index, max(0, len(shown) - 1));

    def run(c: Command) {
        onClose();
        if c.kind == "go" {
            nav(c.to);
        } elif c.kind == "ask" {
            send_event("morrow:ask");
        } else {
            send_event("morrow:command", c.id);
        }
    }

    def on_key(e: any) {
        if e.key == "ArrowDown" {
            e.preventDefault();
            index = (current + 1) % max(1, len(shown));
        } elif e.key == "ArrowUp" {
            e.preventDefault();
            index = (current - 1 + len(shown)) % max(1, len(shown));
        } elif e.key == "Enter" and len(shown) > 0 {
            e.preventDefault();
            run(shown[current]);
        } elif e.key == "Escape" {
            onClose();
        }
    }

    def stop(e: MouseEvent) {
        e.stopPropagation();
    }

    <div className="modal-backdrop palette-backdrop" onClick={lambda (e: MouseEvent) { onClose(); }}>
        <div className="palette ui-card" role="dialog" aria-modal="true" aria-label="Command palette" onClick={stop}>
            <input className="palette-input" autoFocus={True} placeholder="Type a command…"
                aria-label="Command" aria-controls="palette-list" role="combobox" aria-expanded={True}
                value={query} onKeyDown={on_key}
                onChange={lambda (e: ChangeEvent) { query = e.target.value; index = 0; }} />
            <ul className="palette-list" id="palette-list" role="listbox">
                {for (i, c) in enumerate(shown) {
                    <li key={c.id} role="option" aria-selected={i == current}
                        className={"palette-item" + (" on" if i == current else "")}
                        onMouseEnter={lambda (e: MouseEvent) { index = i; }}
                        onClick={lambda (e: MouseEvent) { run(c); }}>
                        <Icon name={c.icon} size={16} />
                        <span className="grow">{c.label}</span>
                        {c.keys and <kbd className="kbd">{c.keys}</kbd>}
                    </li>
                }}
                {(len(shown) == 0) and <li className="palette-empty">No matching command</li>}
            </ul>
        </div>
    </div>
}
