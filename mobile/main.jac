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

    def logout {
        jacLogout();                        # synchronous; clears the stored token
        logged_in = False;
    }

    <View style={styles.screen}>
        {(<TodayScreen onLogout={logout}/>) if logged_in else (<LoginScreen onLoggedIn={lambda { logged_in = True; }}/>)}
    </View>
}
