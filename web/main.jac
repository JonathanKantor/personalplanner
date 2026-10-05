"""web - Entry point of the server and the web client.

This app owns the backend: every endpoint is imported by name below, which is
what registers it at POST /function/<name>. (Jac only reliably registers
endpoints that the entry module names explicitly.) The mobile app and CLI call
these same endpoints over HTTP.
"""

import from core.tasks {
    create_task, list_tasks, get_task, update_task, complete_task, delete_task
}
import from core.preferences { get_preferences, update_preferences }
import from core.seed { seed_demo_data }

# Client-side UI (placeholder until the web slice). JSX makes this client code.

import from .frontend { app as ClientApp }

def:pub app -> JsxElement {
    <ClientApp/>
}
