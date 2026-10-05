# mobile

The planner's phone app: a **mobUI** app (React Native primitives from
`@jac/mobui`), so one source tree runs in a browser (react-native-web) and on
iOS / Android (Expo). See the main README, "Mobile app", for how to run it.

## How it is wired

- `main.jac` - the shell: shows `LoginScreen` or `TodayScreen`.
- `screens/Login.jac` - log in / sign up (same accounts as web and CLI).
- `screens/Today.jac` - one day: classes and blocks, accept/reject
  suggestions, check off tasks, quick-add, Plan.
- `components/` - `ItemRow` (one schedule row), `Button`, `Icon`
  (`Icon.jac` for web, `Icon.native.jac` for phones; keep their icon lists equal).
- `theme.jac` - colors and the StyleSheet. `lib.jac` - date and error helpers.

The app has no server of its own. Every server call is a walker spawn, e.g.
`root spawn DayScreen(day=day)`, handled by the walkers in
`core/mobile_api.jac` (the `mobile_api` service app in `jac.toml`).

Only `@jac/mobui` primitives are allowed here: a raw `<div>` is compile
error E1105.
