# Jonathan Kantor (kantorj) Personal Planner

- **Name:** Jonathan Kantor
- **Uniqname:** kantorj
- **UMID:** `________` <!-- fill in your 8-digit UMID -->

## What it is

**morrow** is a personal schedule planner written in [Jac](https://jaseci.org).
It reads your class schedule from Google Calendar (or an `.ics` file / iCal
link), takes your tasks (typed in, or imported from Canvas), and suggests when
to work on each one: around your classes and meetings, and before its
deadline. You accept, adjust or reject each suggestion. One backend serves four
components (the **server/API**, a **web app**, a **mobile app** and a **CLI**)
on the same accounts and data.

### Main features

- **Calendar import:** Google Calendar (read-only OAuth), `.ics` files or
  private iCal links; mark which calendars or recurring events are classes.
- **Tasks** with a due date, priority, time estimate, course and notes;
  repeating tasks (`WEEKLY:MO,WE`); **Canvas assignments** imported from the
  Canvas calendar feed, with your own estimates.
- **Deterministic scheduler:** fits work into free time in each task's due
  week, before its deadline, respecting working hours, days off, a preferred
  study window, breaks and a daily focus limit. Every suggestion says why it
  was chosen, and anything that doesn't fit says why not.
- **Accept / adjust / reject:** ✓ / ✗ on each suggestion, drag a block to
  move it, click to edit, Accept all, Clear; add your own events (meetings not
  in Google Calendar) and the planner works around them.
- **AI assistant ("Ask Morrow"):** chat to plan ("Plan my week", "Add a
  2-hour paper due Friday 5pm", "I don't work after 8pm"). It can only act
  through the planner's own tools, uses the same scheduler, and lists every
  change it makes. Runs on Google's free Gemini tier.
- **Web app:** week grid and agenda views, a "Coming up" list with weekly
  follow-through, keyboard shortcuts, a Cmd/Ctrl+K command palette, and a
  floating assistant whose eyes follow your mouse.
- **Mobile app** (Expo Go, or a browser) with the same features and look, and
  a **CLI** (`plan suggest`, `plan accept all`, ...).

## Quick start

Prerequisites: macOS or Linux; on macOS 14, Homebrew's `expat` (below); for
the phone app, the **Expo Go** app on a phone on the same network. Google
Calendar and the AI assistant are optional (each needs a key in `.env`, see
below); everything else works with the built-in demo data.

```bash
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash   # Jac
brew install expat                 # macOS 14 only, once
cd personal-assistant
cp .env.example .env               # optional: GEMINI_API_KEY, GOOGLE_CLIENT_ID / _SECRET
source env.sh                      # in every new terminal
jac install                        # project dependencies, once
jac run                            # server + web app: http://localhost:8000
```

Open http://localhost:8000, sign up, then **Settings → Load demo classes and
tasks**, then **Planner → Suggest schedule**. Each step is explained below.

## How the four components fit together

```
            ┌─────────────── one Jac server (jac run) ───────────────┐
 web app ──▶│ def:protect functions  ─┐                              │
 (React,    │  POST /function/<name>  │                              │
  same app) │                         ├─▶ core/ ── per-user graph:   │
 mobile ───▶│ walkers (mobile_api)  ──┤    tasks, blocks, calendars, │
 (Expo Go)  │  POST …/walker/<Name>   │    events, preferences, chat │
 CLI ──────▶│ same HTTP endpoints   ──┘                              │
 (plan …)   └────────────────────────────────────────────────────────┘
```

- **Server / API (`core/`)** holds all the logic: calendar import and sync,
  tasks, the scheduler, the AI assistant, Canvas import. Data lives in each
  user's own graph (Jac nodes and edges under their `root`), so every query is
  automatically scoped to the logged-in user. Login-required endpoints are
  plain Jac functions (`def:protect`); `/docs` lists them all.
- **Web app (`web/`)** is a Jac client app in the same workspace: its pages
  call the server functions directly (`await suggest_schedule(21)`) and Jac
  generates the HTTP calls. The server pre-computes views in your timezone
  (`core/views.jac`), so the browser does no date math.
- **Mobile app (`mobile/`)** is a separate mobUI app (React Native). Jac only
  lets one app call another's *walkers*, so `core/mobile_api.jac` exposes
  login-required walkers, each a thin wrapper around the same core function
  the web uses. Same data, same behaviour.
- **CLI (`cli/`)** is a Jac command-line app that logs in and calls the same
  HTTP endpoints, storing its token in `~/.config/jac-planner/`.

### What makes it impressive

- **One backend, four real clients**, all sharing accounts and data, with no
  logic duplicated: the web, phone, CLI and assistant all go through the same
  core functions and the same scheduler.
- **An explainable, deterministic scheduler** (pure functions, 29 unit tests):
  due-week work windows with overflow, joined sessions, focus limits, breaks,
  preferred hours, rejected slots never re-offered, and a reason on every
  suggestion and every "couldn't fit".
- **A safe AI assistant**: byLLM with tool calling. The model can only use 14
  planner tools (no delete), finds time with the deterministic scheduler
  instead of inventing it, and falls back across free Gemini models when one is
  busy. Tests run with byLLM's `MockLLM`, no key needed.
- **Real integrations**: Google Calendar OAuth (read-only, tokens never in
  git), `.ics` parsing with recurrence, and Canvas feeds (deduplicated,
  re-syncable).
- **Jac features used for what they're for**: graph data model
  (`root -> Task -> ScheduledAs -> TimeBlock`), walkers for the phone,
  `def:protect` endpoints, byLLM, a shared `core/` across a multi-app
  workspace, and Jac test annexes.
- **A designed UI on web and phone** from one set of design tokens, with
  keyboard shortcuts, a command palette, accessibility labels, reduced-motion
  support, and Morrow's eye-tracking avatar.
- **560+ automated tests**: scheduler, parsers and recurrence unit tests, and
  end-to-end tests of every endpoint and walker.

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
  and tasks", then Planner -> "Suggest schedule")
- API docs (every endpoint, try them in the browser): http://localhost:8000/docs
- Run all tests: `jac test` (one file: `jac test core/scheduler.jac`)

### Web app

| Page | What it does |
|---|---|
| `/login` | log in or sign up (same accounts as the phone app and CLI) |
| `/` Planner | week grid (or Agenda): classes in blue, your events, planned work and deadlines in coral (round checkbox = done), suggestions in dashed amber with ✓ / ✗. **Suggest schedule**, **Accept all**, **Clear**; **click** a block or deadline to edit the task (or change a block's time); **drag** a block or your own event to another time or day; **Add task** / **Add event** (one-off or weekly). Right side: **Coming up** and weekly follow-through. Deadlines after the visible hours are listed under the day's date |
| `/tasks` | every task, soonest first: tick to finish or reopen, click to edit or delete, Open / All, Add task |
| `/assistant` | full-page chat with the AI assistant (also the floating "Ask Morrow" button on every page) |
| `/settings` | name, city, hours and limits, days off; Connect Google Calendar; import an `.ics` file or iCal URL; mark calendars / recurring events as classes; **Canvas assignments**; load demo data |
| `/oauth/callback` | where Google returns after the consent screen; finishes the connection |

**Keyboard** (Planner): `T` this week, `←`/`K` and `→`/`J` change week, `N`
add event, `A` add task; **Cmd/Ctrl+K** opens the command palette anywhere.

The pages call server functions directly (`await suggest_schedule(21)`); Jac
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

Web app -> **Ask Morrow** (the floating button, or the Assistant page), or the
phone's Ask Morrow tab: chat to plan, e.g. "Plan my week and explain
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
`by llm(tools=[...])` function. The model can only act through 14 planner
tools (see the calendar, list/add/update/complete tasks, run the scheduler,
accept/reject/move blocks, add events, clear suggestions, read/change
preferences); there is no delete tool.
To find time it runs the same deterministic scheduler as the "Suggest
schedule" button rather than inventing slots, and it accepts suggestions only
when you agree. Your conversation is stored per user (New chat clears it).
Tests use byLLM's `MockLLM` (no key needed): `tests/assistant_api_tests.jac`.

### Mobile app

The phone app has the web app's features and look, as four tabs:

- **Plan**: a week strip (tap a day, ‹ › for weeks), that day's classes,
  events and planned / suggested work (✓ / ✗ on suggestions), what's due
  (tick to finish), **Suggest / Accept all / Clear**, "Couldn't fully
  schedule", and Coming up. Tap an item to edit it in a bottom sheet (tasks:
  every field, mark done, delete; blocks: accept, reject or **change time**;
  your events: edit or delete). **+ Task / + Event** add new ones.
- **Tasks**: soonest first, tick to finish / reopen, tap to edit, Add task.
- **Ask Morrow**: the same assistant and conversation as the web.
- **Settings**: name, city, hours and limits, days off, Canvas import, demo
  data, log out.

Google Calendar, `.ics` uploads, marking classes and dragging blocks are on
the web app. Built with `@jac/mobui` (React Native primitives), so the same
code runs on a phone and in a browser.

**On your phone (Expo Go):** install **Expo Go**, put the phone on the same
network as the laptop (a phone hotspot works; campus Wi-Fi often blocks
device-to-device traffic), stop any other `jac run`, then:

```bash
source env.sh
jac setup mobile                    # once: Expo scaffold into .jac/mobile-rn/ (~0.5 GB)
bash scripts/fix_mobile_native.sh   # once: jac 0.37.14 workaround (see below)
bash scripts/phone_dev.sh           # starts the server + Metro, prints a QR code
```

Scan the QR code with Expo Go (iPhone: the Camera app) and log in with the
same account as the web app. If the app looks stale, shake the phone and tap
Reload. If it won't start, `rm -rf .jac/client/mobile/compiled` and run the
script again.

Use `scripts/phone_dev.sh`, not `jac run --dev mobile` on its own: in jac
0.37.14 that command starts its API server by building a native Android APK,
which fails without the Android SDK ("Invalid or corrupt jarfile ...
gradle-wrapper.jar"). The app still loads (Metro serves it) but has no server,
so login and signup fail. The script runs the real API (`jac run --port 8000
--no-client web`, which includes the mobile walkers, against the web app's
data) on the port the phone is told to use, and restores the API address the
failed build blanks out. The Gradle error still prints once; ignore it.

**In a browser:** `jac build --platform web mobile` builds the phone app for
the web (`.jac/client/mobile/dist/`). Note that `jac run --dev --platform web
mobile` runs its own separate data store, so use your web account's data via
the phone instead.

**Workaround for phones:** in jac 0.37.14 the native runtime that Metro uses
is missing `useJacState`, which the compiler emits for every component's `has`
state, so every screen crashes in Expo Go with "TypeError: undefined is not a
function". `scripts/fix_mobile_native.sh` points Metro's `@jac/runtime` at
`mobile/native-fix/jac_runtime_shim.js`, which re-exports the native runtime
and adds `useJacState` (copied from the browser runtime). Re-run it if you
delete `.jac/mobile-rn`, then restart `scripts/phone_dev.sh`.

The dev setup detects your laptop's LAN address and points the app at it
(Metro on :8081, API on :8000; override with `JAC_RN_DEV_HOST=<ip>`). Native
iOS/Android builds (instead of Expo Go) need Xcode / the Android SDK.

**Why walkers:** the mobile app is a separate app in the workspace, and Jac
only lets one app call another's *walkers* or `def:pub` functions. So its API
is a set of login-required walkers in `core/mobile_api.jac` (one per screen
action, each calling the same core function as the web app), declared as the
`mobile_api` service app in `jac.toml`. `FinishTask` and `DecideBlock` show
graph traversal: they walk `root -> Task -> (ScheduledAs) -> TimeBlock`.
Tests: `tests/mobile_api_tests.jac`; browser smoke test of the screens:
`bash scripts/mobile_smoke.sh`.

### CLI

The CLI talks to the same server, so start it first (`jac run` in another
terminal). Then, from the project folder:

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

`suggest_schedule(days=21)` plans the next 1–28 days and returns suggested
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
   earliest free time, your preferred study window first each day. Work is
   placed in 30–120 min pieces, and the daily focus cap is never exceeded.
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
  styles/           tokens.css (every design value), global, components, calendar
mobile/           the phone app (mobUI): main.jac (tabs), screens/ (Plan, Tasks, Assistant,
                    Settings, Login), components/ (kit, sheets, EventRow, ...), theme.jac, lib.jac
  native-fix/       runtime shim for phones (see "Workaround for phones")
cli/              the `plan` command (talks to the server over HTTP)
  api.jac           HTTP calls + login token storage
  commands.jac      one function per command
  main.jac          argument parsing
bin/plan          wrapper so you can type `plan ...` anywhere
tests/            end-to-end tests of every endpoint and mobile walker
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

