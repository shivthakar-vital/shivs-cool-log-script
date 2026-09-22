#!/usr/bin/env bash
# VERSION: 1.1.0
# Menu front-end for shivs_cool_log_script.sh -- run it as `glm`.
# Every screen just builds a normal command line and prints it before running,
# so anyone who uses this a few times can graduate to typing `gl` directly.
set -euo pipefail
shopt -s nullglob

LOG_ROOT="$HOME"
SCRIPT="$LOG_ROOT/shivs_cool_log_script.sh"
ARCHIVE_DIR="OLD_LOGS"

# ---------------------------------------------------------------------------
# EDIT THIS: devices offered in the picker. "other host..." is always appended,
# so anything missing here can still be typed in by hand.
HOSTS=(
  cherry
  loki
  proto-0028
  tbox-006
)
# ---------------------------------------------------------------------------

CUSTOM_LABEL="+ other host..."

FZF_OPTS=(
  --height=45%
  --layout=reverse
  --border=rounded
  --info=inline
  --pointer='>'
  --no-multi
  --preview-window='right,52%,border-left'
)

# --- data pulled from the main script, so the menu can never drift from it ---

device_types() {
  "$SCRIPT" --list-types | tr ' ' '\n'
}

services_for() {
  "$SCRIPT" --list-services "$1"
}

default_type_for() {
  "$SCRIPT" --default-type "$1"
}

# Turn "cc-driver-integrated.service conductor-integrated.service" into "cc, conductor"
short_services() {
  local s out=""
  for s in $(services_for "$1"); do
    s="${s%.service}"; s="${s%-integrated}"; s="${s%-driver}"
    out="${out:+$out, }$s"
  done
  printf '%s' "$out"
}

# --- previews (this script re-invokes itself; fzf calls these) --------------

preview_host() {
  local h="$1" d base stamp nick drivers f
  for d in "$LOG_ROOT"/LOGS_*/"$h"/*/ "$LOG_ROOT/$ARCHIVE_DIR"/LOGS_*/"$h"/*/; do
    [[ -d "$d" ]] || continue
    printf '%s\n' "${d%/}"
  done | sort -r | head -8 | while read -r d; do
    base="$(basename "$d")"
    stamp="${base%%_*}"
    nick=""
    [[ "$base" == *_* ]] && nick="${base#*_}"
    drivers=""
    for f in "$d"/*_log_*.txt; do
      f="$(basename "$f")"
      f="${f#${h}_}"; f="${f%%_log_*}"; f="${f%_driver}"
      drivers="${drivers:+$drivers,}$f"
    done
    printf '  %s  %-22s %s\n' "${stamp:0:5} ${stamp:9:2}:${stamp:12:2}" "$drivers" "${nick:+($nick)}"
  done
  echo
}

preview_type() {
  local s
  echo "  services pulled:"
  for s in $(services_for "$1"); do
    echo "    $s"
  done
}

case "${1:-}" in
  --preview-host) shift; preview_host "$1"; exit 0 ;;
  --preview-type) shift; preview_type "$1"; exit 0 ;;
esac

# --- order hosts by most recently pulled ------------------------------------

host_last_epoch() {
  local h="$1" d t newest=0
  for d in "$LOG_ROOT"/LOGS_*/"$h" "$LOG_ROOT/$ARCHIVE_DIR"/LOGS_*/"$h"; do
    if [[ -d "$d" ]]; then
      t="$(stat -f %m "$d" 2>/dev/null || echo 0)"
      if [[ "$t" -gt "$newest" ]]; then newest="$t"; fi
    fi
  done
  printf '%s' "$newest"
}

sorted_hosts() {
  local h
  for h in "${HOSTS[@]}"; do
    printf '%s\t%s\n' "$(host_last_epoch "$h")" "$h"
  done | sort -rn | cut -f2
}

[[ -x "$SCRIPT" ]] || { echo "Can't find $SCRIPT" >&2; exit 1; }

cd "$LOG_ROOT"

HOST=""
DEVICE=""
SELF="$LOG_ROOT/shivs_log_menu.sh"

step=host
while true; do
  case "$step" in

  host)
    if ! HOST="$( { sorted_hosts; printf '%s\n' "$CUSTOM_LABEL"; } | fzf "${FZF_OPTS[@]}" \
        --prompt='device> ' \
        --header='pick a device                                ESC to quit' \
        --preview="bash '$SELF' --preview-host {}" )"; then
      exit 0
    fi
    if [[ "$HOST" == "$CUSTOM_LABEL" ]]; then
      printf '  hostname: '
      read -r HOST
      [[ -z "$HOST" ]] && continue
    fi
    step=type
    ;;

  type)
    DEFAULT_TYPE="$(default_type_for "$HOST")"
    TYPE_HEADER="$HOST -- which services?                     ESC back"
    [[ -n "$DEFAULT_TYPE" ]] && \
      TYPE_HEADER="$HOST -- default is '$DEFAULT_TYPE', Enter accepts   ESC back"
    if ! DEVICE="$(device_types | while read -r t; do
          printf '%-6s %s\n' "$t" "$(short_services "$t")"
        done | fzf "${FZF_OPTS[@]}" \
        --query="$DEFAULT_TYPE" \
        --prompt='services> ' \
        --header="$TYPE_HEADER" \
        --preview="bash '$SELF' --preview-type {1}" )"; then
      step=host
      continue
    fi
    DEVICE="${DEVICE%% *}"
    step=when
    ;;

  when)
    if ! WHEN="$(printf '%s\n' \
        'live          follow conductor now (Ctrl-C stops)' \
        '10 min        last 10 minutes' \
        '30 min        last 30 minutes' \
        '60 min        last hour' \
        'today         since midnight' \
        'custom mins   type a number' \
        'range         type start and end times' \
      | fzf "${FZF_OPTS[@]}" --no-preview \
        --prompt='when> ' \
        --header="$HOST / $DEVICE                              ESC back" )"; then
      step=type
      continue
    fi
    WHEN="${WHEN%% *}"
    break
    ;;
  esac
done

# --- build the command ------------------------------------------------------

CMD=("$SCRIPT")

if [[ "$WHEN" == "live" ]]; then
  # Follow mode saves nothing, so there is no nickname to ask for.
  CMD+=("$HOST")
  echo
  echo "  \$ gl $HOST"
  echo
  exec "${CMD[@]}"
fi

SINCE=""; UNTIL=""; MINUTES=""
case "$WHEN" in
  10|30|60)  MINUTES="$WHEN" ;;
  today)     SINCE="today"; UNTIL="now" ;;
  custom)
    printf '  minutes: '
    read -r MINUTES
    [[ "$MINUTES" =~ ^[0-9]+$ ]] || { echo "  not a number, aborting." >&2; exit 1; }
    ;;
  range)
    printf '  start (e.g. %s 09:00:00): ' "$(date +%Y-%m-%d)"
    read -r SINCE
    printf '  end   (e.g. %s 09:30:00): ' "$(date +%Y-%m-%d)"
    read -r UNTIL
    [[ -n "$SINCE" && -n "$UNTIL" ]] || { echo "  need both, aborting." >&2; exit 1; }
    ;;
esac

printf '  nickname (optional, Enter to skip): '
read -r NICK

PRETTY="gl"
if [[ -n "$NICK" ]]; then
  CMD+=(-n "$NICK")
  PRETTY="$PRETTY -n $NICK"
fi
CMD+=("$HOST" "$DEVICE")
PRETTY="$PRETTY $HOST $DEVICE"

if [[ -n "$MINUTES" ]]; then
  CMD+=("$MINUTES")
  PRETTY="$PRETTY $MINUTES"
else
  CMD+=("$SINCE" "$UNTIL")
  PRETTY="$PRETTY '$SINCE' '$UNTIL'"
fi

echo
echo "  \$ $PRETTY"
echo
exec "${CMD[@]}"
