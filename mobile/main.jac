"""mobile - the planner on your phone (mobUI: React Native + web preview).

`app` is the shell: logged in, it shows four tabs - Plan, Tasks, Ask Morrow,
Settings - over a bottom tab bar; otherwise Login. The backend is the web
app's server; screens call it with walkers from core/mobile_api.jac. Only
`@jac/mobui` primitives are allowed in this app (a raw <div> is E1105).

The shell also remembers your last touch (or mouse position, in the web
preview) so Morrow's eyes can look at it (components/MorrowFace.jac).
"""

import from "@jac/mobui" { View, Platform, useWindowDimensions }
import from "@jac/runtime" { jacIsLoggedIn, jacLogout }
import from .theme { styles }
import from .screens.Login { LoginScreen }
import from .screens.Plan { PlanScreen }
import from .screens.Tasks { TasksScreen }
import from .screens.Assistant { AssistantScreen }
import from .screens.Settings { SettingsScreen }
import from .components.TabBar { TabBar }

def:pub app -> JsxElement {
    has logged_in: bool = jacIsLoggedIn(),
        tab: str = "plan",
        pointer: list[float] = [];           # last touch / mouse [x, y] on screen

    # On a phone the saved login token is read from secure storage
    # asynchronously, so the first check above can say "logged out". Wait for
    # the runtime to finish loading it, then check again. (In a browser the
    # promise doesn't exist and this simply re-checks.)
    # In the web preview the page has no height of its own, so give the shell
    # the window's height (phones already fill the screen).
    window = useWindowDimensions();
    fill = {"height": window.height} if Platform.OS == "web" else {};

    async can with entry {
        ready: any = globalThis.__jacPlatformReady__;  # jac:ignore[E1032]
        if ready {
            await ready;
        }
        logged_in = jacIsLoggedIn();
    }

    def logout {
        jacLogout();                        # synchronous; clears the stored token
        logged_in = False;
        tab = "plan";
    }

    """Touch (phone) and pointer (web preview) positions, in screen coordinates."""
    def track(e: any) {
        n: any = e.nativeEvent;
        x: any = n.pageX if n.pageX != None else n.clientX;
        y: any = n.pageY if n.pageY != None else n.clientY;
        if x != None and y != None {
            pointer = [x, y];
        }
    }

    <View style={[styles.screen, fill]} onTouchStart={track} onTouchMove={track} onPointerMove={track}>
        {(
            <View style={styles.screen}>
                {(<PlanScreen/>) if tab == "plan" else <View/>}
                {(<TasksScreen/>) if tab == "tasks" else <View/>}
                {(<AssistantScreen pointer={pointer}/>) if tab == "ask" else <View/>}
                {(<SettingsScreen onLogout={logout}/>) if tab == "settings" else <View/>}
                <TabBar tab={tab} onTab={lambda (t: str) { tab = t; }} pointer={pointer}/>
            </View>
        ) if logged_in else (
            <LoginScreen pointer={pointer} onLoggedIn={lambda { logged_in = True; }}/>
        )}
    </View>
}
