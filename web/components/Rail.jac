"""The slim left icon rail: logo, main sections, "more" menu, avatar."""

import from "@jac/runtime" { Link, useNavigate }
import from .kit { Icon, IconButton, Avatar, NavItem }

glob SECTIONS: list[NavItem] = [
    NavItem(to="/", icon="calendar", label="Planner"),
    NavItem(to="/tasks", icon="tasks", label="Tasks"),
    NavItem(to="/assistant", icon="chat", label="Assistant")
];

glob MORE_LINKS: list[NavItem] = [
    NavItem(to="/canvas", icon="book", label="Import from Canvas"),
    NavItem(to="/settings", icon="settings", label="Settings")
];

def:pub Rail(path: str, name: str) -> JsxElement {
    has more_open: bool = False;
    nav = useNavigate();

    def go(to: str) {
        more_open = False;
        nav(to);
    }

    <nav className="rail" aria-label="Main">
        <Link to="/" className="rail-logo" aria-label="morrow home"><Icon name="sparkles" size={20} /></Link>
        <div className="rail-items">
            {for s in SECTIONS {
                <div key={s.to} className={"rail-slot" + (" active" if path == s.to else "")}>
                    <IconButton icon={s.icon} label={s.label} active={path == s.to}
                        onClick={lambda (e: MouseEvent) { go(s.to); }} />
                </div>
            }}
        </div>
        <span className="spacer"></span>
        <div className="rail-more">
            <IconButton icon="more" label="More" onClick={lambda (e: MouseEvent) { more_open = not more_open; }} />
            {if more_open {
                <div className="menu-backdrop" onClick={lambda (e: MouseEvent) { more_open = False; }}></div>
                <div className="menu rail-menu" role="menu">
                    {for m in MORE_LINKS {
                        <button key={m.to} role="menuitem" className="menu-item" onClick={lambda (e: MouseEvent) { go(m.to); }}>
                            <Icon name={m.icon} /> {m.label}
                        </button>
                    }}
                </div>
            }}
        </div>
        <Avatar name={name} />
    </nav>
}
