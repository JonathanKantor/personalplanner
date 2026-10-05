# Planner

A personal schedule planner written in [Jac](https://jaseci.org). It imports
your class schedule from Google Calendar (or an `.ics` file), takes your tasks
for the week, and recommends time slots around your classes.

One backend serves four clients: a web app, a mobile app, a CLI, and the HTTP
API itself.

> Status: slices 1–2 done (server, tasks, preferences, calendar import/sync).
> Scheduler, CLI, web UI, and mobile app are in progress.

## Setup

Tested on macOS 14.2.1 (Apple Silicon) with jac 0.37.14.

### 1. Install Jac

The official installer is a single self-contained binary (it bundles its own
Python runtime, the web client, mobile support, and the AI integration, so no
separate pip packages are needed):

```bash
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash
jac --version        # expect: jac 0.37.14
```

Python dependencies for this project are installed into a per-project virtual
environment at `.jac/venv` (nothing is installed globally).

### 2. macOS workaround (source `env.sh` in every terminal)

On macOS 14.2, jac's bundled Python can't load the system's (older) XML
library, which breaks `pip` and therefore `jac install`. Homebrew's `expat`
fixes it:

```bash
brew install expat   # once
source env.sh        # in every new terminal, from the project folder
```

`env.sh` also loads `.env` (see below), because `jac run` does not read it on
its own.

### 3. Install project dependencies

```bash
source env.sh
jac install
```

## Running

```bash
source env.sh
jac run                  # server + web app at http://localhost:8000
```

- API docs (every endpoint, try them in the browser): http://localhost:8000/docs
- Run tests: `jac test core/ics.jac`, `jac test core/gcal.jac`, `jac test tests/`

### Demo data (no Google account needed)

After creating an account, call `seed_demo_data` (from `/docs`, or the CLI
once it exists). It creates six tasks plus two calendars for the current week:
"Demo: Classes" (marked as classes) and "Demo: Personal". Running it again
replaces the demo data without touching your own tasks or calendars.

## Calendar import

Three sources, all stored the same way (re-syncing updates events, never
duplicates them):

| Source | Endpoint | Re-sync |
|---|---|---|
| `.ics` file contents | `import_ics(content, name)` | import again with the same name |
| Private iCal URL | `import_ics_url(url, name)` | `sync_calendar` |
| Google (OAuth, read-only) | `google_auth_url` → `connect_google` | `sync_calendar` |

**No-OAuth option:** in Google Calendar, open Settings → (your calendar) →
"Secret address in iCal format", copy it, and pass it to `import_ics_url`.
Treat that URL like a password.

Marking classes: mark a whole calendar with `set_calendar_is_class`, or one
recurring series (e.g. "EECS 376 Lecture", listed by `list_series`) with
`set_series_is_class`. Events are synced from 7 days ago to 120 days ahead.

### Google Calendar setup (OAuth)

1. Go to https://console.cloud.google.com and create a project.
2. **APIs & Services → Library**: search "Google Calendar API" and **Enable** it.
3. **Google Auth Platform → Branding**: set an app name and your email.
4. **Audience**: choose **External**, keep it in **Testing**, and add your own
   Google account under **Test users**.
5. **Data Access → Add or remove scopes**: add
   `https://www.googleapis.com/auth/calendar.readonly`.
6. **Clients → Create client**: type **Web application**, and add the
   authorized redirect URI `http://localhost:8000/oauth/callback`.
7. Copy the client ID and secret into `.env` (git ignores it):

   ```bash
   cp .env.example .env    # then fill in GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET
   source env.sh           # reload so the server sees them
   ```

Notes:
- The planner only asks for read-only access.
- Your refresh token is stored in your own user data on the server, never in
  code or git.
- While the Google app is in "Testing", Google expires refresh tokens after 7
  days, so you will need to reconnect weekly. (Publishing the app removes this
  limit but requires Google's verification for the calendar scope.)
- Disconnect with `disconnect_google`; fully revoke at
  https://myaccount.google.com/permissions.

## Project layout

```
jac.toml          workspace config: apps, dependencies
env.sh            macOS workaround + loads .env
core/             shared backend (no UI)
  models.jac        nodes (stored data) and view objects (API responses)
  timeutil.jac      timezone helpers: store UTC, show local
  changes.jac       validation for partial updates
  tasks.jac         task endpoints
  preferences.jac   preference endpoints
  ics.jac           .ics parsing and recurrence expansion (pure)
  gcal.jac          Google OAuth + sync
  calendars.jac     storing events, class marking, calendar endpoints
  sync.jac          sync_calendar over all sources
  seed.jac          demo data
  *.test.jac        unit tests for the module of the same name
web/              the web app; its main.jac registers every endpoint
tests/            end-to-end endpoint tests
```

## Jac notes (things that surprised us)

- **Endpoints**: `def:protect name(...)` becomes `POST /function/name` and
  requires login. Inside it, `root` is the caller's own root node, so every
  query is automatically scoped to that user. (`:priv` needs the same login but
  stops other files from importing the function, which the entry module must
  do to register it.)
- **Optional endpoint parameters**: in jac 0.37.14 an omitted
  `x: str | None = None` parameter arrives as the string `"None"`. Update
  endpoints therefore take a `changes` dict of only the fields to change.
- **Module names**: don't name a module after a Python standard-library
  module (e.g. `calendar.jac`); it shadows the real one during `jac test`.
