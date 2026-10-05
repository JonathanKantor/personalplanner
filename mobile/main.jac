"""mobile - the planner on your phone (mobUI: React Native + web preview).

`app` is the shell: if you're logged in it shows Today, otherwise Login.
The backend is the web app's server; screens call it with walkers from
core/mobile_api.jac. Only `@jac/mobui` primitives are allowed in this app
(a raw <div> is compile error E1105).
"""

import from "@jac/mobui" { View }
import from "@jac/runtime" { jacIsLoggedIn, jacLogout }
import from .theme { styles }
import from .screens.Login { LoginScreen }
import from .screens.Today { TodayScreen }

def:pub app -> JsxElement {
    has logged_in: bool = jacIsLoggedIn();

    # On a phone the saved login token is read from secure storage
    # asynchronously, so the first check above can say "logged out". Wait for
    # the runtime to finish loading it, then check again. (In a browser the
    # promise doesn't exist and this simply re-checks.)
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
    }

    <View style={styles.screen}>
        {(<TodayScreen onLogout={logout}/>) if logged_in else (<LoginScreen onLoggedIn={lambda { logged_in = True; }}/>)}
    </View>
}
