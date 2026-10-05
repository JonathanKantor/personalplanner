"""/login - log in or create an account.

Uses the same accounts as the CLI (`plan login`): username + password.
"""

import from "@jac/runtime" { jacLogin, jacSignup, SignupResult, useNavigate }

def:pub LoginPage() -> JsxPage {
    has username: str = "",
        password: str = "",
        signing_up: bool = False,
        error: str = "",
        busy: bool = False;
    nav = useNavigate();

    async def submit(e: FormEvent) {
        e.preventDefault();
        # Results of `await` are declared first (see jac-cl-auth: avoids a
        # JS scoping bug in the generated code).
        ok: bool = False;
        created: SignupResult | None = None;
        error = "";
        if not username.strip() or not password {
            error = "Enter a username and password.";
            return;
        }
        busy = True;
        if signing_up {
            created = await jacSignup(username.strip(), password);
            if not created.success {
                busy = False;
                error = created.error or "Could not create the account (username taken?)";
                return;
            }
        }
        # Signup does not start a session, so always log in afterwards.
        ok = await jacLogin(username.strip(), password);
        busy = False;
        if ok {
            nav("/");
        } else {
            error = "Wrong username or password.";
        }
    }

    def toggle(e: MouseEvent) {
        e.preventDefault();
        signing_up = not signing_up;
        error = "";
    }

    <div className="auth panel">
        <h2>{"Create your account" if signing_up else "Log in to Planner"}</h2>
        {error and <div className="error">{error}</div>}
        <form onSubmit={submit}>
            <label className="field">Username
                <input id="username" autoComplete="username" value={username}
                    onChange={lambda (e: ChangeEvent) { username = e.target.value; }} />
            </label>
            <label className="field">Password
                <input id="password" type="password"
                    autoComplete={"new-password" if signing_up else "current-password"}
                    value={password}
                    onChange={lambda (e: ChangeEvent) { password = e.target.value; }} />
            </label>
            <button id="submit" className="btn primary" type="submit" disabled={busy}>
                {"Sign up" if signing_up else "Log in"}
            </button>
        </form>
        <p className="muted">
            {"Already have an account? " if signing_up else "New here? "}
            <a href="#" onClick={toggle}>{"Log in" if signing_up else "Create an account"}</a>
        </p>
    </div>
}
