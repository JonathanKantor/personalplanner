"""Top bar: wordmark, section pills, today's date + city, and the account menu."""

import from "@jac/runtime" { Link, useNavigate, jacLogout }
import from .kit { Icon, Avatar, NavItem }

glob PILLS: list[NavItem] = [NavItem(to="/", icon="calendar", label="Planner"), NavItem(to="/tasks", icon="tasks", label="Tasks")];

def:pub TopBar(path: str, name: str, today: str, city: str) -> JsxElement {
    has menu_open: bool = False;
    nav = useNavigate();

    def go(to: str) {
        menu_open = False;
        nav(to);
    }

    def logout(e: MouseEvent) {
        menu_open = False;
        jacLogout();                                 # synchronous: clears the session
        nav("/login");
    }

    <header className="topbar">
        <Link to="/" className="wordmark"><span className="wordmark-dot"></span>morrow</Link>
        <nav className="pills" aria-label="Sections">
            {for p in PILLS {
                <Link key={p.to} to={p.to} className={"pill" + (" active" if path == p.to else "")}>{p.label}</Link>
            }}
        </nav>
        <span className="spacer"></span>
        <span className="topbar-date num"><Icon name="sun" />{today}{(" · " + city) if city else ""}</span>
        <div className="account">
            <button type="button" className="account-btn" aria-haspopup="menu" aria-expanded={menu_open}
                onClick={lambda (e: MouseEvent) { menu_open = not menu_open; }}>
                <Avatar name={name} />
                <span className="account-name">{name.split(" ")[0]}</span>
                <Icon name="chevron-down" size={14} />
            </button>
            {if menu_open {
                <div className="menu-backdrop" onClick={lambda (e: MouseEvent) { menu_open = False; }}></div>
                <div className="menu account-menu" role="menu">
                    <button role="menuitem" className="menu-item" onClick={lambda (e: MouseEvent) { go("/settings"); }}>
                        <Icon name="settings" /> Settings
                    </button>
                    <button role="menuitem" className="menu-item" onClick={logout}>
                        <Icon name="logout" /> Log out
                    </button>
                </div>
            }}
        </div>
    </header>
}
