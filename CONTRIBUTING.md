# Contributing

Bug reports, fixes and ideas are welcome. Open an issue first for anything
bigger than a small fix, so we can agree on the shape before you build it.

## Where things are

| Path | What it is |
|---|---|
| `bin/phonelink` | The whole tool, in bash: connections, windows, sound, the network map |
| `shell/phonelink.panel/` | The bar icon and panel (QML), and its strings in `i18n/en.json` |
| `hypr/phonelink.lua` | Keybindings and window rules |
| `omarchy/menu.jsonc` | The Phone menu |
| `install.sh`, `uninstall.sh` | Installer and uninstaller |
| `docs/reference.md` | Everything the README leaves out |
| `tests/` | Checks that also run in CI |

## Try your changes

`./install.sh` installs your working copy, so `phonelink`, the bar panel and
the menu all run your code. It restarts the bar, but phone windows that are
already open keep running the version they started with.

To see the scrcpy command a window would run, without opening the window (it
still connects to the phone):

```bash
PHONELINK_DRY_RUN=1 bin/phonelink open com.android.chrome
```

Each window's quality changes and reconnections are logged in
`~/.local/state/phonelink/logs/sessions.log`.

## Test without breaking your own windows

phonelink finds its windows and sound by their processes. A test that calls
`disconnect`, `sound_stop` or anything else that ends sessions will close the
phone windows you have open, even from a test folder. Close them first, or
stub `session_pids`, `pgrep` and `pkill` in the test.

For tests that need adb, use a separate adb server and state folders, so your
phone and settings stay out of it:

```bash
export ANDROID_ADB_SERVER_PORT=5039 ADB_MDNS=0 ADB_MDNS_AUTO_CONNECT=none
export XDG_STATE_HOME=$(mktemp -d) XDG_CONFIG_HOME=$(mktemp -d) XDG_DATA_HOME=$(mktemp -d)
```

`PHONELINK_QUIET=1` turns off notifications.

## Before a pull request

```bash
tests/check.sh
```

It runs everything CI runs. It needs `shellcheck`, `jq` and `lua`
(`omarchy pkg add shellcheck lua`).

Then say in the pull request what you tested on: the phone and Android
version, and the connection (USB, Wi-Fi, direct link or Tailscale).

## Style

- **Short text.** The panel is icons first, with names in tooltips. A
  notification is the fact plus one action: "Unlock your phone", not a
  paragraph. The README stays short; details go in `docs/reference.md`.
- **Bash.** `set -uo pipefail`, ShellCheck clean at warning level. Comments
  say why, and only where the code doesn't. Watch for:
  - `(( x == word ))` reads `word` as a variable;
  - `pgrep -f` and `pkill -f` can match your own shell;
  - a long-running child (adb server, scrcpy, background jobs) must not
    inherit phonelink's lock files; use `close_locks`.
- **Anything from the phone is untrusted.** Check package names with
  `valid_pkg`, show names as plain text in QML (`Text.PlainText`), and quote
  anything sent to the phone's shell.
- **Panel strings** go in `shell/phonelink.panel/i18n/en.json`. Every key must
  be used, and every used key must exist; `tests/check.sh` checks both.
- **Docs.** When behaviour changes, update `docs/reference.md` in the same pull
  request.

## AI agents

`AGENTS.md` is for agents installing phonelink for a user. Agents working on
the code should follow this file instead, and must never run `phonelink stop`
or `phonelink direct off` while the user has phone windows open.
