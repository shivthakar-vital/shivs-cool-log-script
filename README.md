# shivs-cool-log-script

## Updating — run both commands

Already set up? This is how you get the latest version. **Both steps are
required.** `git pull` on its own updates this folder but not the scripts you
actually run, so you'd stay on the old version with no warning.

```bash
cd shivs-cool-log-script && git pull && bash install.sh
```

Re-running the installer is safe: it backs up your current scripts, doesn't
duplicate the `.zshrc` entries, and remembers your account name.

Note that it **replaces** your local copies, so if you customised `HOSTS`,
re-apply that afterwards or restore from the timestamped backup it leaves in
your home directory.

Setting up for the first time instead? Skip to [Setup](#setup).

---

Pull `journalctl` logs off the lab devices without SSHing in by hand, and tail
them live. Two commands: `gl` for the command line, `glm` for a menu.

```
gl cherry              # follow conductor logs live
gl cherry ht 15        # last 15 min of ht driver + conductor, saved to disk
glm                    # pick device / services / timeframe from a menu
```

---

## Setup

Requires macOS with [Homebrew](https://brew.sh). Takes about two minutes.

**1. Install `fzf`** (needed for the `glm` menu):

```bash
brew install fzf
```

**2. Clone and run the installer:**

```bash
git clone https://github.com/shivthakar-vital/shivs-cool-log-script.git
cd shivs-cool-log-script
bash install.sh
```

It asks one question — your account name on the lab devices, i.e. the
`yourname` in `ssh yourname@cherry`. It never asks for a password. Then it:

- copies the scripts to your home directory (backing up anything already there)
- sets `SSH_USER` so you don't have to type `yourname@` every time
- adds `gl` and `glm` to your `~/.zshrc`
- tests each device and tells you which ones still need your SSH key


**3. Reload your shell:**

```bash
source ~/.zshrc
```

That's it. `glm` should now open the menu.

---

## Usage

### Live tail

A hostname on its own follows `conductor-integrated.service` in real time.
Ctrl-C stops it. Nothing is written to disk.

```bash
gl cherry
```

### Fetch logs

```bash
gl <host> <type> [minutes]           # default 10 minutes
gl <host> <type> <since> <until>     # explicit range
```

```bash
gl cherry ht                              # last 10 minutes
gl cherry ht 45                           # last 45 minutes
gl cherry ht '09:30:00' '10:15:00'        # today, between those times
gl cherry ht '2026-09-20 14:00' 'now'     # across days
```

Times are `journalctl` strings, so `today`, `yesterday`, `-2h` and `now` all
work. Quote anything containing a space.

### Service types

| type   | services pulled                           |
|--------|-------------------------------------------|
| `cc`   | cc driver + conductor                     |
| `ht`   | ht driver + conductor                     |
| `ia`   | ia driver + conductor                     |
| `vkg`  | cc + ch drivers + conductor               |
| `inst` | cc, ht, ia, ch drivers + conductor        |
| `nuc`  | the `qa-cc-1c` variants                   |

### Nicknames

`-n` labels a pull so you can find it later. It lands on the folder and on
every file inside it.

```bash
gl -n coilfault cherry ht 30
```

```
LOGS_09_22_26/cherry/09-22-26T14-02-11_coilfault/
  cherry_ht_driver_log_09-22-26T14-02-11_coilfault.txt
  cherry_conductor_log_09-22-26T14-02-11_coilfault.txt
```

The flag can go anywhere on the line. Characters outside `A-Za-z0-9._-` become
underscores.

### The menu

```bash
glm
```

Walks you through device, then services, then timeframe, then an optional
nickname. Type to filter, arrows to move, **ESC** to step back. It prints the
equivalent `gl` command before running it, so you can learn the shorthand and
stop using the menu when you're ready.

The device list shows your recent pulls for each host, including nicknames.

Devices that always use the same services have that type pre-selected, so you
can just press Enter — `cherry` and `proto-0028` come up on `inst`, `loki` on
`vkg`. Backspace to clear it and pick something else. This is a menu
convenience only; `gl` on the command line always wants the type spelled out.

---

## Where logs go

Everything lands in your home directory, grouped by day, then device, then run:

```
~/LOGS_09_22_26/cherry/09-22-26T14-02-11_coilfault/*.txt
```

Folders from previous days get swept into `~/OLD_LOGS/` automatically on your
next pull. To archive today's folder early:

```bash
gl archive
```

---

## Configuration

Both files have a clearly marked block near the top.

**`~/shivs_cool_log_script.sh`** — your lab account name. The installer sets
this; edit it if it changes.

```bash
SSH_USER="yourname"
```

You can override it per-run without editing anything:

```bash
LOG_SSH_USER=someoneelse gl cherry
```

**`~/shivs_log_menu.sh`** — which devices appear in the `glm` picker. Anything
not listed can still be reached with `+ other host...`, or by using `gl`
directly.

```bash
HOSTS=(
  cherry
  loki
  proto-0028
  tbox-006
)
```

**`~/shivs_cool_log_script.sh`** — the type each device normally uses, which
is what the menu pre-selects. Devices not listed here just open the picker with
nothing filled in.

```bash
default_type_for() {
  case "${1#rpi-}" in
  cherry|proto-0028)  echo "inst" ;;
  loki)               echo "vkg" ;;
  *)                  echo "" ;;
  esac
}
```

Service types themselves live in `services_for()` in the same file, and the
menu asks the script for them at runtime — so adding a type there makes it show
up in the menu with no second edit.

---

## Troubleshooting

**`zsh: command not found: gl`** — your shell hasn't re-read its config.
`source ~/.zshrc`, or open a new terminal.

**"not connected" / permission denied** — `SSH_USER` is probably empty or
wrong. Every prompt now echoes the full target, so check what it prints:

```
Fetching ht-driver-integrated.service from yourname@cherry -> ...
```

If there's no `yourname@`, set it in `~/shivs_cool_log_script.sh`.

**Asked for a password on every run** — your SSH key isn't on that device yet.
Run `ssh-copy-id yourname@<host>` once.

**`-- No entries --`** — the fetch worked; those services just logged nothing
in that window. Widen the timeframe.

**`glm` does nothing / command not found** — `fzf` isn't installed.
`brew install fzf`.
