"""Root layout: wraps every page. `<Outlet/>` is where the current page renders.

Logged in: the morrow shell (left icon rail + top bar). On the login page
(or logged out) the page renders alone.
Returning `JsxLayout` is what makes this file a layout (file-based routing).
"""

import from "react" { useEffect }
import from "@jac/runtime" { Outlet, useLocation, jacIsLoggedIn }
import from core.preferences { get_preferences }
import from ..components.Rail { Rail }
import from ..components.TopBar { TopBar }
import from ..components.AskMorrow { AskMorrow }
import from ..components.CommandPalette { CommandPalette }
import from ..lib.ui { current_username, today_label }

def:pub Shell() -> JsxLayout {
    has name: str = "",
        city: str = "",
        tz: str = "America/Detroit",
        palette: bool = False;               # Cmd/Ctrl+K command palette open
    # Hooks first, before any conditional rendering (React's rules of hooks).
    location = useLocation();
    path = location.pathname;
    logged_in = jacIsLoggedIn();
    shell = logged_in and path != "/login";

    # Cmd+K (Mac) / Ctrl+K anywhere toggles the command palette.
    useEffect(lambda {
        def on_key(e: any) {
            if (e.metaKey or e.ctrlKey) and str(e.key).lower() == "k" {
                e.preventDefault();
                palette = not palette;
            }
        }
        window.addEventListener("keydown", on_key);
        return lambda { window.removeEventListener("keydown", on_key); };
    }, [palette]);

    # Load the name/city/timezone for the header; again on each navigation so
    # changes saved in Settings show up.
    async can with [path] entry {
        if not (jacIsLoggedIn() and path != "/login") {
            return;
        }
        try {
            p = await get_preferences();
            tz = p.timezone;
            city = p.city;
            name = p.display_name or (await current_username()) or "You";
        } except Exception {}
    }

    if not shell {
        return <main className="page"><Outlet /></main>;
    }
    return <div className="shell">
        <Rail path={path} name={name or "You"} />
        <div className="shell-main">
            <TopBar path={path} name={name or "You"} today={today_label(tz)} city={city}
                onPalette={lambda { palette = True; }} />
            <main className="page"><Outlet /></main>
        </div>
        {(path != "/assistant") and <AskMorrow />}
        {palette and <CommandPalette path={path} onClose={lambda { palette = False; }} />}
    </div>;
}
