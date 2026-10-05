"""plan - the planner's command-line client.

Run through the wrapper:  bin/plan <command>   (or: jac run cli -- <command>)
Each subcommand is an argparse parser whose `func` points at a function in
cli/commands.jac; main() just parses and dispatches.
"""

import argparse;
import sys;
import from cli.api { CliError }
import from cli.commands {
    cmd_login, cmd_logout, cmd_whoami, cmd_add, cmd_list, cmd_done, cmd_edit,
    cmd_rm, cmd_suggest, cmd_accept, cmd_reject, cmd_move, cmd_today, cmd_week,
    cmd_progress, cmd_clear, cmd_event, cmd_sync, cmd_import, cmd_calendars, cmd_mark_class,
    cmd_connect_google, cmd_disconnect_google, cmd_prefs, cmd_seed
}

def build_parser -> argparse.ArgumentParser {
    parser = argparse.ArgumentParser(
        prog="plan", description="Personal schedule planner",
        epilog="Ids can be shortened to their first few characters."
    );
    sub = parser.add_subparsers(dest="command", required=True, metavar="<command>");

    def add(name: str, func: any, help: str) -> argparse.ArgumentParser {
        p = sub.add_parser(name, help=help, description=help);
        p.set_defaults(func=func);
        return p;
    }

    # account
    p = add("login", cmd_login, "Log in (saves a token in ~/.config/jac-planner)");
    p.add_argument("username", nargs="?");
    p.add_argument("--server", help="server URL (default http://localhost:8000)");
    p.set_defaults(signup=False);
    p = add("signup", cmd_login, "Create an account and log in");
    p.add_argument("username", nargs="?");
    p.add_argument("--server");
    p.set_defaults(signup=True);
    add("logout", cmd_logout, "Forget the saved token");
    add("whoami", cmd_whoami, "Show who you're logged in as");

    # tasks
    p = add("add", cmd_add, "Add a task");
    p.add_argument("title");
    p.add_argument("--due", required=True, help='e.g. fri, "fri 17:00", tomorrow, 2026-10-09');
    p.add_argument("--priority", "-p", `default="medium", choices=["low", "medium", "high"]);
    p.add_argument("--est", type=int, `default=60, help="estimated minutes (default 60)");
    p.add_argument("--course", "-c", help="course or category");
    p.add_argument("--notes");
    p.add_argument("--repeat", help="DAILY or WEEKLY:MO,WE[;UNTIL=YYYY-MM-DD]");
    p = add("list", cmd_list, "List open tasks");
    p.add_argument("--all", action="store_true", help="include finished tasks");
    p.add_argument("--done", action="store_true", help="only finished tasks");
    p = add("done", cmd_done, "Mark task(s) done");
    p.add_argument("ids", nargs="+");
    p = add("edit", cmd_edit, "Change a task");
    p.add_argument("id");
    p.add_argument("--title");
    p.add_argument("--due");
    p.add_argument("--priority", "-p", choices=["low", "medium", "high"]);
    p.add_argument("--est", type=int);
    p.add_argument("--course", "-c");
    p.add_argument("--notes");
    p.add_argument("--repeat", help='"" to stop repeating');
    p = add("rm", cmd_rm, "Delete a task");
    p.add_argument("id");

    # planning
    p = add("suggest", cmd_suggest, "Suggest time slots for your tasks");
    p.add_argument("--days", type=int, `default=7, help="how far ahead to plan (1-28, default 7)");
    p = add("accept", cmd_accept, "Accept suggested block(s), or 'all'");
    p.add_argument("ids", nargs="+");
    p = add("reject", cmd_reject, "Reject suggested block(s)");
    p.add_argument("ids", nargs="+");
    p = add("move", cmd_move, "Move/resize a block (accepts it)");
    p.add_argument("id");
    p.add_argument("start", help='e.g. "tue 15:00" or 2026-10-20T15:00');
    p.add_argument("end");
    add("clear", cmd_clear, "Remove all pending suggestions (planned blocks stay)");
    p = add("event", cmd_event, "Add a meeting/commitment that isn't in Google Calendar");
    p.add_argument("title");
    p.add_argument("--date", required=True, help='e.g. tue, tomorrow, 2026-10-09');
    p.add_argument("--start", required=True, help="HH:MM, e.g. 15:00");
    p.add_argument("--end", required=True, help="HH:MM");
    p.add_argument("--weeks", type=int, `default=1, help="repeat weekly this many times");
    p.add_argument("--class", dest="is_class", action="store_true", help="counts as a class");
    add("today", cmd_today, "Today's classes, events and planned blocks");
    p = add("week", cmd_week, "This week, day by day");
    p.add_argument("--next", action="store_true", help="next week instead");
    add("progress", cmd_progress, "This week's numbers");

    # calendars
    add("sync", cmd_sync, "Re-sync Google and iCal-URL calendars");
    p = add("import", cmd_import, "Import an .ics file or a private iCal URL");
    p.add_argument("source", help="path to .ics, or https:// / webcal:// URL");
    p.add_argument("--name", help="calendar name (default: from the file)");
    add("calendars", cmd_calendars, "List calendars and recurring events");
    p = add("mark-class", cmd_mark_class, "Mark a calendar or recurring event as class time");
    p.add_argument("id", help="calendar id or recurring-event id from plan calendars");
    p.add_argument("--off", action="store_true", help="unmark");
    add("connect-google", cmd_connect_google, "Connect Google Calendar (read-only)");
    add("disconnect-google", cmd_disconnect_google, "Disconnect Google Calendar");

    # settings
    p = add("prefs", cmd_prefs, "Show or change preferences");
    p.add_argument("--set", nargs="+", metavar="KEY=VALUE",
                   help="e.g. --set work_start=08:30 days_off=sat,sun max_focus_minutes_per_day=300");
    add("seed", cmd_seed, "Load demo tasks and classes for this week");
    return parser;
}

def main(argv: list[str]) -> int {
    args = build_parser().parse_args(argv);
    try {
        args.func(args);
    } except CliError as e {
        print(f"error: {str(e)}", file=sys.stderr);
        return 1;
    } except KeyboardInterrupt {
        return 130;
    }
    return 0;
}

with entry:__main__ {
    sys.`exit(main(sys.argv[1:]));
}
