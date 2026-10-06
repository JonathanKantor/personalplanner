# mobile

The planner's phone app: a **mobUI** app (React Native primitives from
`@jac/mobui`), so one source tree runs in a browser (react-native-web) and on
iOS / Android (Expo). See the main README, "Mobile app", for how to run it.

It has the same look ("morrow": cream, white cards, terracotta) and the same
features as the web app, laid out for a phone.

## How it is wired

- `main.jac` - the shell: Login, or four tabs over a bottom tab bar. It also
  remembers your last touch so Morrow's eyes can follow it.
- `screens/`
  - `Plan.jac` - the web Planner on a phone: week strip, the chosen day's
    classes / events / planned and suggested work, what's due, Suggest /
    Accept all / Clear, "Couldn't fully schedule", and Coming up. Tap an item
    to edit it; + Task / + Event add new ones.
  - `Tasks.jac` - every task, soonest due first; round checkbox to finish or
    reopen; tap to edit; Add task.
  - `Assistant.jac` - Ask Morrow: the same AI assistant (and conversation)
    as the web app.
  - `Settings.jac` - name, city, hours and limits, days off, Canvas import,
    demo data, log out.
  - `Login.jac` - log in / sign up (same accounts as web and CLI).
- `components/`
  - `kit.jac` - Button, Card, Chip, CheckCircle, Segmented, PageHeader,
    Field, Sheet (bottom-sheet dialog) - the phone version of the web kit.
  - `EventRow.jac` (one calendar item, coloured like the web blocks),
    `WeekStrip.jac`, `ComingUpCard.jac`, `TaskSheet.jac`, `EventSheet.jac`,
    `DayPicker.jac` (mobUI has no native date picker), `CanvasSection.jac`,
    `MorrowFace.jac`, `TabBar.jac`, and `Icon` (`Icon.jac` for web,
    `Icon.native.jac` for phones; keep their icon lists equal).
- `theme.jac` - colours (the web tokens), spacing, sizes and the StyleSheet.
  `lib.jac` - date, time and error helpers.

The app has no server of its own. Every server call is a walker spawn, e.g.
`root spawn WeekScreen(start=...)`, handled by the walkers in
`core/mobile_api.jac` (the `mobile_api` service app in `jac.toml`). Each
walker calls the same core function the web app uses, so both behave the
same; run the phone against the web app's server (`scripts/phone_dev.sh`) so
they also share the same data.

Only `@jac/mobui` primitives are allowed here: a raw `<div>` is compile
error E1105.

Not on the phone (use the web app): connecting Google Calendar, uploading
.ics files, marking which calendar events are classes, and dragging blocks
(on the phone, open a block and use Change time).
