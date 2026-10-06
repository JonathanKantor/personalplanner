# Jonathan Kantor (kantorj) Personal Planner

A personal schedule planner written in [Jac](https://jaseci.org). It imports
your class schedule from Google Calendar (or an `.ics` file), takes your tasks
for the week, and recommends time slots around your classes.

One backend serves four clients: a web app, a mobile app, a CLI, and the HTTP
API itself.

> Status: server, scheduler, CLI, web app and mobile app done.

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

- Web app: http://localhost:8000 (sign up, then Settings -> "Load demo classes
  and tasks", then Week -> "Suggest schedule")
- API docs (every endpoint, try them in the browser): http://localhost:8000/docs
- Run all tests: `jac test` (one file: `jac test core/scheduler.jac`)

### Web app

| Page | What it does |
|---|---|
| `/login` | log in or sign up (same accounts as the CLI) |
| `/` Week | classes, events and planned blocks in one grid; **Suggest schedule**; accept ✓ / reject ✗ in the grid, or Accept / Adjust / Reject with the reason in the Suggestions list; **click** a block or a "due:" label to edit the task; **drag** a block to another time or day (snaps to 15 min, keeps its length; moving a suggestion accepts it; drops onto classes/events/other planned blocks are refused); **+ Add event** for meetings not in Google Calendar (one-off or weekly; click to edit/delete, drag to move); **Clear suggestions** removes all pending suggestions (planned blocks stay); prev/next week |
| `/tasks` | add tasks; click a task (or Edit) to edit, complete or delete it |
| `/settings` | preferences, Connect Google Calendar, import an `.ics` file or iCal URL, mark calendars / recurring events as classes, load demo data |
| `/oauth/callback` | where Google returns after the consent screen; finishes the connection |

The pages call server functions directly (`await suggest_schedule(7)`); Jac
generates the HTTP calls. Times are converted to your timezone on the server
(`core/views.jac`), so the browser does no timezone math.

### Canvas assignments -> tasks

Web app -> **Settings -> Canvas assignments** (also in the rail's "..." menu
and the Cmd/Ctrl+K palette; the old `/canvas` URL redirects there). In Canvas, open Calendar and copy the "Calendar
Feed" link (bottom right; it's private, like a password), paste it, and
press **Load assignments**. Tick the ones to import, set each estimate (or
"Estimate for all ticked"), priority and course, then **Import**.

- Only assignments are read (UIDs `event-assignment-...`, or links to
  assignments/quizzes/discussions); section meetings in the feed are ignored.
  The course comes from the `[EECS 449 001 FA 2026]` suffix, shortened to
  `EECS 449`. All-day due dates mean 11:59pm.
- **Sync** later: imported tasks get Canvas's current due date and title (your
  estimate is kept); only new assignments are offered. Unticked ones are
  remembered as skipped. Each task stores its Canvas UID, so nothing is
  duplicated.
- Endpoints: `canvas_sync(url)`, `canvas_import(choices)`, `canvas_feed_url()`,
  `canvas_forget()` in `core/canvas.jac`.

### AI planning assistant

Web app -> **Assistant** tab: chat to plan, e.g. "Plan my week and explain
it", "Add a 2-hour paper due Friday 5pm", "I don't want to work after 8pm",
"When am I free Thursday afternoon?". Each reply lists what it changed.

Setup (free): get a Gemini API key at https://aistudio.google.com/apikey
(sign in with a Google account; no credit card), put `GEMINI_API_KEY=...` in
`.env`, then restart the server (`source env.sh && jac run`). The assistant
uses a byLLM `ModelPool` that tries `gemini-3.6-flash`, then
`gemini-3.5-flash-lite`, then `gemini-3.1-flash-lite`, so a busy model (Gemini's
free tier often answers "503 high demand") falls through to the next. Google
retires models (gemini-2.5-flash is closed to new keys); to change the list set
`BYLLM_DEFAULT_MODEL` in `.env`, e.g. `gemini/gemini-3.8-flash,gemini/gemini-3.5-flash-lite`.
Failures are logged on the server as "assistant failed: ...".

How it works (`core/assistant.jac`, Jac's byLLM): `_assistant_turn` is a
`by llm(tools=[...])` function. The model can only act through 12 planner
tools (see the calendar, list/add/update/complete tasks, run the scheduler,
accept/reject/move blocks, read/change preferences); there is no delete tool.
To find time it runs the same deterministic scheduler as the "Suggest
schedule" button rather than inventing slots, and it accepts suggestions only
when you agree. Your conversation is stored per user (New chat clears it).
Tests use byLLM's `MockLLM` (no key needed): `tests/assistant_api_tests.jac`.

### Mobile app

Today's schedule (classes + planned blocks), accept ✓ / reject ✗ suggestions,
check off tasks, quick-add, and a Plan button. Built with `@jac/mobui`
(React Native primitives: `View`, `Text`, `Pressable`, `TextInput`), so the
same code runs in a browser and on a phone.

```bash
source env.sh
jac run --dev --platform web mobile    # app: http://localhost:8000  (API on :8001)
```

Open it in a phone-sized browser window (or the browser's device toolbar).
The dev server runs the mobile backend (`core/mobile_api.jac`) itself, against
the same database as the web app, so log in with the same account. Run either
this or the web app's `jac run`, not both at once (they share the dev build
folder and the ports).

On a real phone: install **Expo Go**, put the phone on the same Wi-Fi as the
laptop, then (the setup step needs ~0.5 GB of disk for the Expo install)

```bash
jac setup mobile                    # one-time Expo scaffold into .jac/mobile-rn/
bash scripts/fix_mobile_native.sh   # one-time jac 0.37.14 workaround (see below)
bash scripts/phone_dev.sh           # prints a QR code; scan it with Expo Go
```

Use `scripts/phone_dev.sh`, not `jac run --dev mobile` on its own: in jac
0.37.14 that command starts its API server by building a native Android APK,
which fails without the Android SDK ("Invalid or corrupt jarfile ...
gradle-wrapper.jar"). The app still loads (Metro serves it) but has no server,
so login and signup fail. The script runs the real API (`jac run --port 8000
--no-client web`, which includes the mobile walkers) on the port the phone is
told to use, and restores the API address the failed build blanks out. The
Gradle error still prints once; ignore it.

**Workaround for phones:** in jac 0.37.14 the native runtime that Metro uses
is missing `useJacState`, which the compiler emits for every component's `has`
state, so every screen crashes in Expo Go with "TypeError: undefined is not a
function". `scripts/fix_mobile_native.sh` points Metro's `@jac/runtime` at
`mobile/native-fix/jac_runtime_shim.js`, which re-exports the native runtime
and adds `useJacState` (copied from the browser runtime). Re-run it if you
delete `.jac/mobile-rn`, and restart `jac run --dev mobile` after running it.

`--dev` detects your laptop's LAN address and points the app at it (Metro on
:8081, API on :8000; override with `JAC_RN_DEV_HOST=<ip>`). Verified here: the
Expo setup, the dev server, and that Metro's iOS bundle includes the fix. Not
verified here: the app running on a phone.
Campus Wi-Fi often blocks device-to-device connections; a phone hotspot or
home network avoids that. Native iOS/Android builds need Xcode / the Android SDK.

**Why walkers:** the mobile app is a separate app in the workspace, and Jac
only lets one app call another's *walkers* or `def:pub` functions. So its API
is five login-required walkers in `core/mobile_api.jac`, declared as the
`mobile_api` service app in `jac.toml`. `FinishTask` and `DecideBlock` show
graph traversal: they walk `root -> Task -> (ScheduledAs) -> TimeBlock`.

Smoke test (with the mobile dev server running): `bash scripts/mobile_smoke.sh`

### CLI

The server must be running (`jac run` in another terminal). Then:

```bash
export PATH="$PATH:$(pwd)/bin"      # once per terminal (or add to ~/.zshrc)
plan signup alice                    # or: plan login alice
plan seed                            # demo classes + tasks
plan add "PS5" --due "thu 17:00" --priority high --est 90 --course "EECS 376"
plan suggest                         # proposed slots, each with a reason
plan accept 3f9a1c                   # or: plan accept all / plan reject <id>
plan move 3f9a1c "tue 15:00" "tue 16:30"
plan today                           # plan week [--next]
plan done 8c21e0
plan event "Advisor meeting" --date thu --start 15:00 --end 16:00   # --weeks 10 to repeat
plan clear                           # remove all pending suggestions
plan sync                            # re-sync Google / iCal-URL calendars
plan --help                          # every command
```

- `--due` accepts `today`, `tomorrow`, `fri`, `"fri 17:00"`, `2026-10-09`, or
  `"2026-10-09 17:00"`.
- Ids are shown as 6 characters; any unique prefix works.
- `plan login` stores your session token in `~/.config/jac-planner/config.json`
  (mode 600). `plan logout` deletes it. Point at another server with
  `plan login --server https://...` or `PLAN_SERVER=...`.
- `bin/plan` is a small wrapper for `jac run cli -- <command>`.

**Connecting Google from the terminal:** `plan connect-google` opens Google's
consent page. After you approve, the browser lands on
`http://localhost:8000/oauth/callback?code=...`; copy that whole address back
into the terminal. Then `plan calendars` and `plan mark-class <id>` for your
class calendar or courses.

### Demo data (no Google account needed)

After creating an account, run `plan seed` (or call `seed_demo_data` from
`/docs`). It creates six tasks plus two calendars for the current week (next
week, if run on a weekend):
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

## Scheduling

`suggest_schedule(days=7)` plans the next 1–28 days and returns suggested
blocks, each with a reason, plus any task that didn't fit and why:

```
Mon 13:30-15:30  Problem set 4   Free 1:30pm-6pm Monday, due Tuesday 11pm, high priority (session 1 of 3)
NOT PLACED  Rewrite thesis: Only 165 of 900 min fit before Tuesday 12pm: the 240-min daily focus limit is reached
```

How it works (`core/scheduler.jac`, deterministic, 29 tests). The web button and
the assistant plan 3 weeks ahead (`suggest_schedule(days=21)`):

1. **Free time** = working hours on working days − calendar events − accepted
   blocks, keeping the minimum break around each. All-day events don't block.
2. **Order**: earliest due date, then higher priority, then shorter task.
3. **Work window**: each task is worked on close to its deadline, from the
   Monday of its due week (or 3 days before the due date, if earlier, so a
   Monday deadline can use the weekend) up to the deadline. Inside it: the
   earliest free time, your preferred study window first each day. Sessions
   are 30–120 min (long tasks are split), and the daily focus cap is never
   exceeded.
4. **Overflow**: if the window is full, the rest goes into the days just
   before it, nearest first (the block's reason says "earlier than its due
   week"). Tasks whose window hasn't started yet are left for a later plan.
5. **One block per stretch**: back-to-back sessions of a task (only a break
   apart) are joined into one continuous block; sessions are only split where
   something else is in between. Planned blocks of one task that end up next
   to each other (accept, accept all, drag) are merged the same way.
6. **Can't fit**: the part that fits is still suggested; the rest is reported
   with the reason (deadline passed, daily cap, or no free time). On the web,
   that list drops tasks you finish, delete or fully plan.

Deadlines are moments, not time: in the week grid a deadline is a short
marker at its due time, and ones due outside the visible hours (e.g. 11:59pm)
are listed under the day's date.

Then `accept_block`, `reject_block`, `adjust_block(id, start, end)` (also
accepts; refuses clashes), or `accept_all`. Re-planning never moves accepted
blocks, and a rejected slot isn't offered to that task again. Adding, changing,
completing or deleting a task (or changing preferences) automatically
re-plans any pending suggestions.

Recurring tasks: `recurrence` is `DAILY` or `WEEKLY:MO,WE` (optionally
`;UNTIL=2026-12-15`). Each occurrence becomes its own task when planning.

Views: `get_today`, `get_agenda(start, days)` (events + blocks + due tasks),
`get_progress` (this week's numbers).

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
  scheduler.jac     the scheduling algorithm (pure, no database)
  recurrence.jac    recurring-task rules (pure)
  planner.jac       runs the scheduler on your stored data (engine glue)
  planning.jac      planning endpoints: suggest/accept/reject/adjust, agenda, progress
  views.jac         ready-to-draw day/week views in your timezone (web + mobile)
  mobile_api.jac    walkers the mobile app calls (the `mobile_api` service app)
  canvas.jac        Canvas calendar feed -> tasks (parse, sync, import)
  events.jac        your own events ("My events" calendar): create/update/delete
  assistant.jac     AI chat assistant: byLLM function + planner tools
  seed.jac          demo data
  *.test.jac        unit tests for the module of the same name
web/              the web app; its main.jac registers every endpoint
  pages/            one file per URL (file-based routing); (auth)/ = login required
  components/       kit.jac (Button, Card, Chip, Dialog, ...), WeekGrid, EventBlock, ComingUp,
                    AskMorrow + AssistantChat, CommandPalette, CanvasImport, editors
  lib/ui.jac        error-message and time helpers
  styles/global.css
mobile/           the phone app (mobUI): main.jac, screens/, components/, theme.jac, lib.jac
  native-fix/       runtime shim for phones (see "Workaround for phones")
cli/              the `plan` command (talks to the server over HTTP)
  api.jac           HTTP calls + login token storage
  commands.jac      one function per command
  main.jac          argument parsing
bin/plan          wrapper so you can type `plan ...` anywhere
tests/            end-to-end endpoint tests
```

## Jac notes (things that surprised us)

- **Endpoints**: `def:protect name(...)` becomes `POST /function/name` and
  requires login. Inside it, `root` is the caller's own root node, so every
  query is automatically scoped to that user. (`:priv` needs the same login but
  stops other files from importing the function, which the entry module must
  do to register it.)
- **Omitted endpoint parameters**: in jac 0.37.14, when a caller leaves out a
  parameter that has a default, it arrives as the *string* of the default
  (`None` -> `"None"`, `7` -> `"7"`, `False` -> `"False"`). Only `str`
  defaults are safe. Update endpoints take a `changes` dict instead, and int
  parameters go through `as_int` (see `core/changes.jac`).
- **Test annexes**: a `glob` in a `*.test.jac` file runs before the module's
  own declarations exist; use a function instead.
- **Server anchors**: Jac decides per module whether code also goes to the
  browser. A module of pure Jac (no Python import) that pages import endpoints
  from gets compiled for the browser too, and its imports of server-only
  helpers then break the build (E5082). Each endpoint module therefore has a
  Python import, commented as a "server anchor".
- **Client imports of server types** use `import type from core.models {...}`;
  a plain import duplicates the class the generated RPC stub already defines.
- **Don't pin endpoint modules** in `[placement.pins]`: in 0.37.14 a pinned
  endpoint's browser stub loses its parameters (calls arrive with no arguments).
- **Production web build**: `jac build web` (the sealed deploy artifact)
  rejects browser calls to `def:protect` functions (E5082); only `def:pub`
  functions and walkers get browser stubs there. `jac run` (dev) works. See
  "Known limitations".
- **"Sources changed during preparation"** on `jac run`: Jac checks that no
  file in the project folder changes while it compiles, including hidden
  files. A Finder window open on the project folder rewrites `.DS_Store`
  during the compile, so it fails every time. Fix: close that Finder window,
  or lock the file once with `chflags uchg .DS_Store` (undo:
  `chflags nouchg .DS_Store`). This repo's `.DS_Store` is locked.
- **`jac run` flags go before the app name**: `jac run --port 8010 web`
  works; `jac run web --port 8010` silently ignores the port.
- **`jacLogin(username, password)`**: the bundled client-auth guide says
  `email`, but usernames work (verified); the CLI and web share accounts.
- **Module names**: don't name a module after a Python standard-library
  module (e.g. `calendar.jac`); it shadows the real one during `jac test`.

## Known limitations

- `jac build web` (production artifact) currently fails: the web pages call
  login-protected `def:protect` functions, which the sealed build won't
  expose to the browser. Development mode (`jac run`) is unaffected. Fix
  options: switch the web pages to walkers (like the mobile app), or make the
  endpoints `def:pub` with an explicit "must be logged in" check.
- The phone (Expo Go) path needs two jac 0.37.14 workarounds
  (`scripts/fix_mobile_native.sh` once, then `scripts/phone_dev.sh`).
- In dev mode, server errors include a Python traceback in the response
  (`details`); the apps only show the message.

