"""Root layout: wraps every page. `<Outlet/>` is where the current page renders.

Returning `JsxLayout` is what makes this file a layout (file-based routing).
"""

import from "@jac/runtime" { Outlet, Link, useLocation, useNavigate, jacIsLoggedIn, jacLogout }

def:pub Shell() -> JsxLayout {
    # Hooks first, before any conditional rendering (React's rules of hooks).
    location = useLocation();
    nav = useNavigate();
    path = location.pathname;
    logged_in = jacIsLoggedIn();

    def link_class(target: str) -> str {
        return "navlink active" if path == target else "navlink";
    }

    def logout(e: MouseEvent) {
        jacLogout();                       # synchronous: clears the session
        nav("/login");
    }

    <div>
        {if logged_in and path != "/login" {
            <nav className="topbar">
                <span className="brand">Planner</span>
                <Link to="/" className={link_class("/")}>Week</Link>
                <Link to="/tasks" className={link_class("/tasks")}>Tasks</Link>
                <Link to="/settings" className={link_class("/settings")}>Settings</Link>
                <span className="spacer"></span>
                <button className="btn small" onClick={logout}>Log out</button>
            </nav>
        }}
        <main className="page"><Outlet /></main>
    </div>
}
