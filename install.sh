#!/usr/bin/env bash
# Sets up the lab log tools (gl / glm) on macOS or on Windows under Git Bash.
# Run from the folder that contains it:  bash install.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MAIN="shivs_cool_log_script.sh"
MENU="shivs_log_menu.sh"
MARK_OPEN="# >>> lab log tools >>>"
MARK_CLOSE="# <<< lab log tools <<<"

say()  { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
warn() { printf '   !! %s\n' "$*" >&2; }

# --- 0. which platform are we on -------------------------------------------
case "$(uname -s)" in
  Darwin)
    OS="macOS"
    RC="$HOME/.zshrc"
    FZF_HINT="brew install fzf"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    OS="Windows (Git Bash)"
    RC="$HOME/.bashrc"
    FZF_HINT="winget install fzf      (or: scoop install fzf)"
    ;;
  *)
    OS="Linux"
    RC="$HOME/.bashrc"
    FZF_HINT="sudo apt install fzf     (or your distro's package manager)"
    ;;
esac

# GNU sed wants `-i`, BSD sed wants `-i ''`.
sed_inplace() {
  if sed --version >/dev/null 2>&1; then
    sed -i -e "$1" "$2"
  else
    sed -i '' -e "$1" "$2"
  fi
}

for f in "$MAIN" "$MENU"; do
  [[ -f "$HERE/$f" ]] || { warn "missing $f -- copy the whole folder, not just install.sh"; exit 1; }
done

# --- 1. dependencies --------------------------------------------------------
step "Checking what's installed"
say "   platform: $OS"
say "   ssh:      $(command -v ssh || echo MISSING)"
say "   fzf:      $(command -v fzf || echo 'MISSING (needed for glm only)')"
if ! command -v ssh >/dev/null; then
  warn "No ssh found."
  [[ "$OS" == Windows* ]] && warn "Reinstall Git for Windows and keep the bundled OpenSSH."
  exit 1
fi
if ! command -v fzf >/dev/null; then
  warn "fzf is missing. Install it, then re-run this script:"
  warn "    $FZF_HINT"
  warn "(gl will still work without it; glm won't.)"
fi

# --- 2. lab username --------------------------------------------------------
step "Your account name on the lab devices"
say "   This is the part before the @ in: ssh YOURNAME@cherry"
say "   It is NOT your password -- nothing here ever asks for one."
# On an upgrade, default to whatever was set last time instead of re-asking blind.
DEFAULT_USER="${USER:-${USERNAME:-}}"
if [[ -f "$HOME/$MAIN" ]]; then
  PREV="$(sed -n 's/^SSH_USER="\([^"]*\)"$/\1/p' "$HOME/$MAIN" | head -1)"
  [[ -n "$PREV" ]] && DEFAULT_USER="$PREV"
fi
printf '   account name [%s]: ' "$DEFAULT_USER"
read -r LAB_USER
LAB_USER="${LAB_USER:-$DEFAULT_USER}"
if ! [[ "$LAB_USER" =~ ^[A-Za-z0-9._-]+$ ]]; then
  warn "'$LAB_USER' has characters I won't paste into a script. Stopping."
  exit 1
fi

# --- 3. install the scripts -------------------------------------------------
step "Installing scripts into $HOME"
for f in "$MAIN" "$MENU"; do
  if [[ -e "$HOME/$f" ]]; then
    cp "$HOME/$f" "$HOME/$f.backup-$(date +%Y%m%d%H%M%S)"
    say "   backed up existing $f"
  fi
  cp "$HERE/$f" "$HOME/$f"
  chmod +x "$HOME/$f"
  say "   installed $f"
done

# Only the literal empty default is replaced, never an already-set value.
if grep -q '^SSH_USER=""' "$HOME/$MAIN"; then
  sed_inplace "s/^SSH_USER=\"\"/SSH_USER=\"$LAB_USER\"/" "$HOME/$MAIN"
  say "   set SSH_USER=\"$LAB_USER\""
fi

# --- 4. shell functions -----------------------------------------------------
step "Adding gl / glm to $RC"
touch "$RC"
if grep -qF "$MARK_OPEN" "$RC" 2>/dev/null; then
  say "   already present, leaving it alone"
else
  cat >> "$RC" <<EOF

$MARK_OPEN
# Always run from home so logs land in ~/LOGS_*
gl()  { (cd ~ && ./$MAIN "\$@"); }
glm() { (cd ~ && ./$MENU); }
$MARK_CLOSE
EOF
  say "   added"
fi

# Git Bash reads ~/.bash_profile, which does not always pull in ~/.bashrc.
if [[ "$OS" == Windows* ]]; then
  BP="$HOME/.bash_profile"
  if [[ ! -f "$BP" ]] || ! grep -q '\.bashrc' "$BP"; then
    printf '\n[ -f ~/.bashrc ] && . ~/.bashrc\n' >> "$BP"
    say "   pointed ~/.bash_profile at ~/.bashrc"
  fi
fi

# --- 5. connectivity --------------------------------------------------------
step "Testing passwordless access"
HOSTS="$(sed -n '/^HOSTS=(/,/^)/p' "$HOME/$MENU" | sed -n 's/^  \([A-Za-z0-9._-]*\)$/\1/p')"
NEEDS_KEY=""
for h in $HOSTS; do
  if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
         "$LAB_USER@$h" true 2>/dev/null; then
    say "   OK        $LAB_USER@$h"
  else
    say "   needs key $LAB_USER@$h"
    NEEDS_KEY="$NEEDS_KEY $h"
  fi
done

if [[ -n "$NEEDS_KEY" ]]; then
  step "One more step: install your SSH key"
  if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    say "   You have no SSH key yet. Create one with:"
    say "       ssh-keygen -t ed25519"
    say ""
  fi
  say "   Then run this once per device. Each will ask for your LAB password --"
  say "   type it straight into that prompt; it is not stored anywhere."
  for h in $NEEDS_KEY; do
    if command -v ssh-copy-id >/dev/null 2>&1; then
      say "       ssh-copy-id $LAB_USER@$h"
    else
      # Some Git for Windows builds ship without ssh-copy-id.
      say "       cat ~/.ssh/id_ed25519.pub | ssh $LAB_USER@$h \"mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys\""
    fi
  done
fi

step "Done"
say "   Open a new terminal (or: source $RC), then try:"
say "       glm              menu"
say "       gl cherry        live conductor logs"
say "       gl cherry ht 15  last 15 min of ht + conductor"
