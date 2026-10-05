"""HTTP client for the planner server, plus login-token storage.

The CLI is a thin client: it never touches the database. Every command is a
POST to /function/<name> on the server with `Authorization: Bearer <token>`.
That token comes from the server's built-in /user/login endpoint and is saved
to ~/.config/jac-planner/config.json, readable only by you (mode 600).
"""

import json;
import os;
import requests;
import from pathlib { Path }

# $PLAN_CONFIG_DIR overrides the location (used by tests and demos).
glob CONFIG_DIR: Path = Path(os.environ.get("PLAN_CONFIG_DIR") or Path.home() / ".config" / "jac-planner"),
     CONFIG_FILE: Path = CONFIG_DIR / "config.json",
     DEFAULT_SERVER: str = "http://localhost:8000";

"""Raised for anything the user should see as a one-line error."""
class CliError(Exception) {}

def load_config -> dict {
    if CONFIG_FILE.exists() {
        return json.loads(CONFIG_FILE.read_text());
    }
    return {};
}

def save_config(cfg: dict) -> None {
    CONFIG_DIR.mkdir(parents=True, exist_ok=True);
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2));
    os.chmod(CONFIG_FILE, 0o600);            # the token is a password-equivalent
}

"""Server URL: $PLAN_SERVER, else the one saved at login, else localhost."""
def server_url -> str {
    return os.environ.get("PLAN_SERVER") or load_config().get("server") or DEFAULT_SERVER;
}

def _post(path: str, body: dict, token: str = "") -> dict {
    headers = {"Content-Type": "application/json"};
    if token {
        headers["Authorization"] = f"Bearer {token}";
    }
    url = server_url().rstrip("/") + path;
    try {
        resp = requests.post(url, json=body, headers=headers, timeout=60);
    } except requests.ConnectionError {
        raise CliError(f"Can't reach the server at {server_url()}. Start it with: source env.sh && jac run");
    }
    try {
        data = resp.json();
    } except ValueError {
        raise CliError(f"Unexpected response from server ({resp.status_code})");
    }
    if resp.status_code == 401 {
        raise CliError("Not logged in (or your session expired). Run: plan login");
    }
    if not data.get("ok") {
        err = data.get("error") or {};
        raise CliError(err.get("message") or f"Request failed ({resp.status_code})");
    }
    return data.get("data") or {};
}

"""Call a server function and return its result, e.g. call("list_tasks", status="all").
(The first parameter isn't called `name` because some endpoints take a `name` argument.)"""
def call(function: str, **args: any) -> any {
    token = load_config().get("token", "");
    if not token {
        raise CliError("Not logged in. Run: plan login   (or plan signup)");
    }
    return _post(f"/function/{function}", args, token)["result"];
}

def login(username: str, password: str) -> str {
    data = _post("/user/login", {
        "identity": {"type": "username", "value": username},
        "credential": {"type": "password", "password": password}
    });
    return data["token"];
}

def signup(username: str, password: str) -> str {
    data = _post("/user/register", {
        "identities": [{"type": "username", "value": username}],
        "credential": {"type": "password", "password": password}
    });
    return data.get("token") or login(username, password);
}
