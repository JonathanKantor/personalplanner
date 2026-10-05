"""One function per CLI command. Each takes the parsed argparse arguments.

Ids: the server's ids are 32 hex characters; the CLI shows the first 6 and
accepts any unique prefix (like git does with commit hashes).
"""

import getpass;
import os;
import webbrowser;
import from datetime { datetime, timedelta }
import from zoneinfo { ZoneInfo }
import from urllib.parse { urlparse, parse_qs }
import from cli.api { call, login, signup, load_config, save_config, server_url, CliError }

glob WEEKDAYS: list[str] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];

# ------------------------------------------------------------------ helpers

def short(id: str) -> str {
    return id[:6];
}

def _tz -> ZoneInfo {
    return ZoneInfo(call("get_preferences")["timezone"]);
}

def _local(iso: str, tz: ZoneInfo) -> datetime {
    return datetime.fromisoformat(iso).astimezone(tz);
}

def _hm(iso: str, tz: ZoneInfo) -> str {
    return _local(iso, tz).strftime("%H:%M");
}

def _when(iso: str, tz: ZoneInfo) -> str {
    d = _local(iso, tz);
    return d.strftime("%a %b ") + str(d.day) + d.strftime(" %H:%M");
}

"""Turn friendly due dates into what the server accepts (local time):
"today", "tomorrow", "fri", "fri 17:00", "2026-10-09", "2026-10-09 17:00"."""
def resolve_due(text: str, tz: ZoneInfo) -> str {
    parts = text.strip().lower().split();
    if not parts {
        raise CliError("--due is required, e.g. --due fri or --due 2026-10-09");
    }
    word = parts[0];
    clock = parts[1] if len(parts) > 1 else "";
    today = datetime.now(tz).date();
    day = None;
    if word == "today" {
        day = today;
    } elif word == "tomorrow" {
        day = today + timedelta(days=1);
    } elif word[:3] in WEEKDAYS and word.isalpha() {
        ahead = (WEEKDAYS.index(word[:3]) - today.weekday()) % 7;
        day = today + timedelta(days=ahead or 7);        # "fri" on a Friday = next Friday
    }
    if day is None {
        if not word[:1].isdigit() {
            raise CliError(f"Can't read '{text}'. Use today, tomorrow, fri, \"fri 17:00\", 2026-10-09 or \"2026-10-09 17:00\"");
        }
        return text.strip().replace(" ", "T");          # ISO date[/time]; server validates
    }
    return day.isoformat() + (f"T{clock}" if clock else "");
}

def _resolve(prefix: str, items: list[dict], kind: str) -> dict {
    matches = [i for i in items if i["id"].startswith(prefix)];
    if not matches {
        raise CliError(f"No {kind} with id starting '{prefix}'");
    }
    if len(matches) > 1 {
        raise CliError(f"'{prefix}' matches {len(matches)} {kind}s; type more of the id");
    }
    return matches[0];
}

def _task(prefix: str) -> dict {
    return _resolve(prefix, call("list_tasks", status="all"), "task");
}

def _block(prefix: str) -> dict {
    start = (datetime.now() - timedelta(days=14)).date().isoformat();
    return _resolve(prefix, call("list_blocks", start=start, days=60, status=""), "block");
}

def _print_tasks(tasks: list[dict], tz: ZoneInfo) -> None {
    if not tasks {
        print("  (none)");
        return;
    }
    for t in tasks {
        flag = {"done": "x", "scheduled": "~"}.get(t["status"], " ");
        course = f" [{t['category']}]" if t["category"] else "";
        repeat = f" (repeats {t['recurrence']})" if t["recurrence"] else "";
        print(f"  [{flag}] {short(t['id'])}  {t['title']}{course}{repeat}");
        print(f"             due {_when(t['due'], tz)} · {t['priority']} · {t['estimated_minutes']} min");
    }
}

"""Print events and blocks together in time order, one line each."""
def _print_timeline(events: list[dict], blocks: list[dict], tz: ZoneInfo) -> None {
    rows: list[tuple] = [];
    for e in events {
        if e["all_day"] {
            rows.append((e["start"], f"  all day      {e['title']}"));
        } else {
            kind = "class" if e["is_class"] else "event";
            rows.append((e["start"], f"  {_hm(e['start'], tz)}-{_hm(e['end'], tz)}  {kind:<6} {e['title']}"));
        }
    }
    for b in blocks {
        mark = "plan  " if b["status"] == "accepted" else "maybe?";
        rows.append((b["start"], f"  {_hm(b['start'], tz)}-{_hm(b['end'], tz)}  {mark} {b['task_title']}  ({short(b['id'])})"));
    }
    rows.sort(key=lambda (r: tuple) { r[0]; });
    if not rows {
        print("  (nothing scheduled)");
    }
    for (_, line) in rows {
        print(line);
    }
}

# ------------------------------------------------------------------ account

def cmd_login(args: any) -> None {
    cfg = load_config();
    if args.server {
        cfg["server"] = args.server.rstrip("/");
        save_config(cfg);
    }
    username = args.username or input("Username: ");
    password = getpass.getpass("Password: ");
    token = signup(username, password) if args.signup else login(username, password);
    cfg = load_config();
    cfg["token"] = token;
    cfg["username"] = username;
    save_config(cfg);
    print(f"Logged in as {username} on {server_url()}.");
}

def cmd_logout(args: any) -> None {
    cfg = load_config();
    cfg.pop("token", None);
    save_config(cfg);
    print("Logged out.");
}

def cmd_whoami(args: any) -> None {
    cfg = load_config();
    if not cfg.get("token") {
        print(f"Not logged in (server {server_url()}).");
        return;
    }
    p = call("get_preferences");
    print(f"{cfg.get('username', '?')} on {server_url()} (timezone {p['timezone']})");
}

# ------------------------------------------------------------------ tasks

def cmd_add(args: any) -> None {
    tz = _tz();
    t = call(
        "create_task", title=args.title, due=resolve_due(args.due, tz),
        priority=args.priority, estimated_minutes=args.est, notes=args.notes or "",
        category=args.course or "", recurrence=args.repeat or ""
    );
    print(f"Added {short(t['id'])}  {t['title']}, due {_when(t['due'], tz)}.");
}

def cmd_list(args: any) -> None {
    status = "all" if args.all else ("done" if args.done else "");
    _print_tasks(call("list_tasks", status=status), _tz());
}

def cmd_done(args: any) -> None {
    for prefix in args.ids {
        t = call("complete_task", id=_task(prefix)["id"]);
        print(f"Done: {t['title']}");
    }
}

def cmd_edit(args: any) -> None {
    task = _task(args.id);
    changes: dict = {};
    if args.title {
        changes["title"] = args.title;
    }
    if args.due {
        changes["due"] = resolve_due(args.due, _tz());
    }
    if args.priority {
        changes["priority"] = args.priority;
    }
    if args.est is not None {
        changes["estimated_minutes"] = args.est;
    }
    if args.course is not None {
        changes["category"] = args.course;
    }
    if args.notes is not None {
        changes["notes"] = args.notes;
    }
    if args.repeat is not None {
        changes["recurrence"] = args.repeat;
    }
    if not changes {
        raise CliError("Nothing to change; pass e.g. --due fri or --est 90");
    }
    t = call("update_task", id=task["id"], changes=changes);
    print(f"Updated {short(t['id'])}  {t['title']}.");
}

def cmd_rm(args: any) -> None {
    task = _task(args.id);
    call("delete_task", id=task["id"]);
    print(f"Deleted: {task['title']}");
}

# ------------------------------------------------------------------ planning

def cmd_suggest(args: any) -> None {
    tz = _tz();
    plan = call("suggest_schedule", days=args.days);
    blocks = plan["suggestions"];
    if blocks {
        print(f"Suggested ({len(blocks)}):");
        for b in blocks {
            print(f"  {short(b['id'])}  {_when(b['start'], tz)}-{_hm(b['end'], tz)}  {b['task_title']}");
            print(f"          {b['reason']}");
        }
        print("\nAccept: plan accept <id> [<id>...]  |  plan accept all");
        print("Reject: plan reject <id>          |  Move: plan move <id> \"tue 15:00\" \"tue 16:00\"");
    } else {
        print("Nothing to suggest: no open tasks need time.");
    }
    for u in plan["unscheduled"] {
        print(f"\n  ! {u['title']}: {u['reason']}");
    }
}

def cmd_accept(args: any) -> None {
    if args.ids == ["all"] {
        done = call("accept_all");
        print(f"Accepted {len(done)} block(s).");
        return;
    }
    for prefix in args.ids {
        b = call("accept_block", id=_block(prefix)["id"]);
        print(f"Accepted: {b['task_title']}");
    }
}

def cmd_reject(args: any) -> None {
    for prefix in args.ids {
        b = call("reject_block", id=_block(prefix)["id"]);
        print(f"Rejected: {b['task_title']} (run plan suggest for another slot)");
    }
}

def cmd_move(args: any) -> None {
    tz = _tz();
    b = call(
        "adjust_block", id=_block(args.id)["id"],
        start=resolve_due(args.start, tz), end=resolve_due(args.end, tz)
    );
    print(f"Moved and accepted: {b['task_title']} {_when(b['start'], tz)}-{_hm(b['end'], tz)}");
}

def cmd_today(args: any) -> None {
    tz = _tz();
    a = call("get_today");
    print(datetime.now(tz).strftime("Today, %A %B ") + str(datetime.now(tz).day));
    _print_timeline(a["events"], a["blocks"], tz);
    open_due = [t for t in a["due"] if t["status"] != "done"];
    if open_due {
        print("\nDue today:");
        _print_tasks(open_due, tz);
    }
}

def cmd_week(args: any) -> None {
    tz = _tz();
    monday = datetime.now(tz).date() - timedelta(days=datetime.now(tz).weekday());
    if args.next {
        monday = monday + timedelta(days=7);
    }
    a = call("get_agenda", start=monday.isoformat(), days=7);
    for i in range(7) {
        day = monday + timedelta(days=i);
        events = [e for e in a["events"] if _local(e["start"], tz).date() == day];
        blocks = [b for b in a["blocks"] if _local(b["start"], tz).date() == day];
        print(f"\n{day.strftime('%A %b')} {day.day}");
        _print_timeline(events, blocks, tz);
    }
    suggested = len([b for b in a["blocks"] if b["status"] == "suggested"]);
    if suggested {
        print(f"\n{suggested} suggestion(s) waiting (maybe?). Accept with: plan accept <id> | plan accept all");
    }
}

def cmd_progress(args: any) -> None {
    p = call("get_progress");
    print(f"This week: {p['tasks_done']} done, {p['tasks_open']} open ({p['tasks_overdue']} overdue)");
    print(f"Planned focus time: {p['minutes_planned']} min, of which {p['minutes_completed']} min on finished tasks");
}

# ------------------------------------------------------------------ calendars

def cmd_sync(args: any) -> None {
    results = call("sync_calendar");
    if not results {
        print("Nothing to sync. Connect Google (plan connect-google) or add an iCal URL (plan import <url>).");
    }
    for r in results {
        print(f"  {r['calendar']}: {r['added']} added, {r['updated']} updated, {r['removed']} removed ({r['total']} events)");
    }
}

def cmd_import(args: any) -> None {
    source = args.source;
    if source.startswith(("http://", "https://", "webcal://")) {
        r = call("import_ics_url", url=source, name=args.name or "");
    } else {
        # bin/plan changes directory, so resolve relative paths against where you ran it.
        path = os.path.join(os.environ.get("PLAN_CWD", os.getcwd()), os.path.expanduser(source));
        if not os.path.isfile(path) {
            raise CliError(f"No such file: {source}");
        }
        with open(path, encoding="utf-8") as f {
            r = call("import_ics", content=f.read(), name=args.name or "");
        }
    }
    print(f"{r['calendar']}: {r['added']} added, {r['updated']} updated, {r['removed']} removed ({r['total']} events)");
}

def cmd_calendars(args: any) -> None {
    print("Calendars:");
    for c in call("list_calendars") {
        cls = "classes " if c["is_class"] else "        ";
        print(f"  {short(c['id'])}  {cls} {c['name']} ({c['source']}, {c['event_count']} events)");
    }
    series = call("list_series");
    if series {
        print("\nRecurring events:");
        for s in series {
            cls = "class " if s["is_class"] else "      ";
            print(f"  {s['series_id']:<20}  {cls} {s['title']} ({s['occurrences']}x, {s['calendar']})");
        }
    }
    print("\nMark as class: plan mark-class <id>   (undo: --off)");
}

def cmd_mark_class(args: any) -> None {
    on = not args.off;
    cals = [c for c in call("list_calendars") if c["id"].startswith(args.id)];
    series = [s for s in call("list_series") if s["series_id"].startswith(args.id)];
    if len(cals) + len(series) != 1 {
        raise CliError(f"'{args.id}' matches {len(cals) + len(series)} calendars/series; see plan calendars");
    }
    if cals {
        call("set_calendar_is_class", calendar_id=cals[0]["id"], is_class=on);
        print(f"Calendar '{cals[0]['name']}' {'is' if on else 'is no longer'} classes.");
    } else {
        call("set_series_is_class", series_id=series[0]["series_id"], is_class=on);
        print(f"'{series[0]['title']}' {'is' if on else 'is no longer'} a class.");
    }
}

"""Connect Google Calendar from the terminal: open the sign-in page, then
paste back the address the browser lands on."""
def cmd_connect_google(args: any) -> None {
    url = call("google_auth_url");
    print("1. Approve read-only calendar access in your browser:");
    print(f"\n   {url}\n");
    webbrowser.open(url);
    print("2. Your browser then lands on http://localhost:8000/oauth/callback?... ");
    print("   (the page itself may look empty - that's fine). Copy that full address.");
    pasted = input("\nPaste it here: ").strip();
    query = parse_qs(urlparse(pasted).query);
    if "error" in query {
        raise CliError(f"Google said: {query['error'][0]}");
    }
    if "code" not in query or "state" not in query {
        raise CliError("That address has no ?code=...&state=...; copy the full address bar");
    }
    results = call("connect_google", code=query["code"][0], state=query["state"][0]);
    print(f"\nConnected. Imported {len(results)} calendar(s):");
    for r in results {
        print(f"  {r['calendar']}: {r['total']} events");
    }
    print("\nNext: plan calendars, then plan mark-class <id> for your class calendar or courses.");
}

def cmd_disconnect_google(args: any) -> None {
    call("disconnect_google");
    print("Disconnected Google and removed its calendars from the planner.");
}

# ------------------------------------------------------------------ settings

glob INT_PREFS: list[str] = ["min_break_minutes", "max_focus_minutes_per_day"];

def cmd_prefs(args: any) -> None {
    if args.set {
        changes: dict = {};
        for item in args.set {
            if "=" not in item {
                raise CliError(f"Use key=value, e.g. --set work_start=08:30 (got '{item}')");
            }
            (key, value) = item.split("=", 1);
            if key in INT_PREFS {
                changes[key] = int(value);
            } elif key == "days_off" {
                changes[key] = [d for d in value.split(",") if d];
            } else {
                changes[key] = value;
            }
        }
        call("update_preferences", changes=changes);
    }
    p = call("get_preferences");
    for (k, v) in p.items() {
        if not k.startswith("_") {
            print(f"  {k:<26} {', '.join(v) if isinstance(v, list) else v}");
        }
    }
}

def cmd_seed(args: any) -> None {
    r = call("seed_demo_data");
    print(f"Demo data: {r['tasks_created']} tasks and {len(r['calendars'])} calendars for this week.");
    print("Try: plan week, then plan suggest");
}
