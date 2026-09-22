#!/usr/bin/env bash
# VERSION: 2.7.0
set -euo pipefail
shopt -s nullglob

ARCHIVE_DIR="OLD_LOGS"

# ---------------------------------------------------------------------------
# EDIT THIS: your account name on the lab devices -- the "shivthakar" part of
# shivthakar@cherry. Leave it empty to use your local Mac username, which only
# works when the two happen to match.
SSH_USER=""
# ---------------------------------------------------------------------------
# Override without editing the file, handy for testing another account:
#   LOG_SSH_USER=someone gl cherry
SSH_USER="${LOG_SSH_USER:-$SSH_USER}"

# Prints "user@host" when SSH_USER is set, bare "host" otherwise.
ssh_target() {
  if [[ -n "$SSH_USER" ]]; then
    printf '%s@%s' "$SSH_USER" "$1"
  else
    printf '%s' "$1"
  fi
}

# Add/edit service lists here. Keys are the device_type argument.
# (Plain case statement instead of an associative array so this also
# works on macOS's default bash 3.2, which has no `declare -A`.)
services_for() {
  case "$1" in
  cc)         echo "cc-driver-integrated.service conductor-integrated.service" ;;
  ht)         echo "ht-driver-integrated.service conductor-integrated.service" ;;
  ia)         echo "ia-driver-integrated.service conductor-integrated.service" ;;
  nuc)        echo "cc-driver-qa-cc-1c.service conductor-qa-cc-1c.service" ;;
  inst)       echo "cc-driver-integrated.service ht-driver-integrated.service ia-driver-integrated.service ch-driver-integrated.service conductor-integrated.service" ;;
  vkg)        echo "cc-driver-integrated.service ch-driver-integrated.service conductor-integrated.service" ;;
  *)          echo "" ;;
  esac
}

device_types() {
  echo "cc ht ia nuc inst vkg"
}


# ---------------------------------------------------------------------------
# EDIT THIS: the service list each device normally uses. This is used by the
# glm menu only -- it pre-selects the type so you can just press Enter. The
# command line always requires the type spelled out.
default_type_for() {
  case "${1#rpi-}" in
  cherry|proto-0028)  echo "inst" ;;
  loki)               echo "vkg" ;;
  *)                  echo "" ;;
  esac
}
# ---------------------------------------------------------------------------

usage() {
  echo "Usage:" >&2
  echo "  $0 <host>                                    follow conductor logs live (Ctrl-C stops)" >&2
  echo "  $0 [-n <nick>] <host> <type> [minutes]       fetch last N minutes (default 10)" >&2
  echo "  $0 [-n <nick>] <host> <type> <since> <until> fetch a specific time range" >&2
  echo "  $0 archive                                   archive today's LOGS_* folder now" >&2
  echo "" >&2
  echo "  host:         SSH host, e.g. rpi-tbn28. On its own, streams" >&2
  echo "                conductor-integrated.service live; nothing is saved." >&2
  echo "  type:         one of: $(device_types)  (required)" >&2
  echo "  minutes:      how many minutes of logs to pull, e.g. 10 (default: 10)" >&2
  echo "  since/until:  journalctl time strings, e.g. '12:00:00' or '2026-07-14 12:00:00'" >&2
  echo "  -n nickname:  label appended to every log filename, after the timestamp." >&2
  echo "                May appear anywhere on the line. Characters outside" >&2
  echo "                [A-Za-z0-9._-] are replaced with '_'." >&2
  exit 1
}

# Merge dir "$1" into "$ARCHIVE_DIR/$1". Safe to call even if that archive
# folder already exists (e.g. archived manually earlier today, then swept up
# again by the automatic archive on the next run) -- it merges instead of
# erroring or clobbering.
archive_dir() {
  local d="$1"
  mkdir -p "$ARCHIVE_DIR/$d"
  rsync -a --remove-source-files "$d"/ "$ARCHIVE_DIR/$d"/
  find "$d" -depth -type d -empty -delete
}

# Small query interface so the menu front-end never has to parse this file.
case "${1:-}" in
  --list-types)    device_types; exit 0 ;;
  --list-services) services_for "${2:-}"; exit 0 ;;
  --default-type)  default_type_for "${2:-}"; exit 0 ;;
esac

# Pull the -n/--name flag out first so it can sit anywhere on the line, then
# hand the remaining words back to the positional parsing below untouched.
NICKNAME=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)
      [[ $# -lt 2 ]] && { echo "$1 requires a nickname" >&2; usage; }
      NICKNAME="$2"
      shift 2
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done
# ${ARGS[@]+...} guards against set -u tripping on an empty array under bash 3.2.
set -- ${ARGS[@]+"${ARGS[@]}"}

# Keep the nickname safe to paste into a filename.
SUFFIX=""
if [[ -n "$NICKNAME" ]]; then
  SUFFIX="_${NICKNAME//[^A-Za-z0-9._-]/_}"
fi

[[ $# -lt 1 ]] && usage

if [[ "$1" == "archive" ]]; then
  [[ $# -ne 1 ]] && usage
  TODAY_DIR="LOGS_$(date +%m_%d_%y)"
  if [[ -d "$TODAY_DIR" ]]; then
    echo "Archiving $TODAY_DIR -> $ARCHIVE_DIR/$TODAY_DIR"
    archive_dir "$TODAY_DIR"
  else
    echo "No $TODAY_DIR folder found, nothing to archive."
  fi
  exit 0
fi

# A bare host and nothing else: stream the conductor journal to the terminal
# instead of saving anything. -t forces a remote TTY so Ctrl-C tears journalctl
# down on the far end, and exec hands off signal handling so Ctrl-C is a clean
# exit rather than a set -e abort.
if [[ $# -eq 1 ]]; then
  echo "Following conductor-integrated.service on $(ssh_target "$1") -- Ctrl-C to stop." >&2
  exec ssh -t "$(ssh_target "$1")" "journalctl -u conductor-integrated.service -f"
fi

[[ $# -lt 2 || $# -gt 4 ]] && usage

HOST="$1"
DEVICE_TYPE="$2"

MODE="minutes"
WINDOW="10"
SINCE=""
UNTIL=""

if [[ $# -eq 4 ]]; then
  MODE="range"
  SINCE="$3"
  UNTIL="$4"
elif [[ $# -eq 3 ]]; then
  WINDOW="$3"
  if ! [[ "$WINDOW" =~ ^[0-9]+$ ]]; then
    echo "minutes must be a plain integer, got '$WINDOW'" >&2
    exit 1
  fi
fi

SERVICES="$(services_for "$DEVICE_TYPE")"
if [[ -z "$SERVICES" ]]; then
  echo "Unknown device type '$DEVICE_TYPE'. Valid: $(device_types)" >&2
  exit 1
fi

HOST_SHORT="${HOST#rpi-}"
OUT_DIR="LOGS_$(date +%m_%d_%y)"
TIMESTAMP="$(date +%m-%d-%yT%H-%M-%S)"

# Archive any LOGS_* folder left over from a previous day, automatically.
for d in LOGS_*/; do
  d="${d%/}"
  [[ "$d" == "$OUT_DIR" ]] && continue
  echo "Archiving old logs: $d -> $ARCHIVE_DIR/$d"
  archive_dir "$d"
done

# Each run gets its own timestamped subfolder under the device's folder.
RUN_DIR="$OUT_DIR/$HOST_SHORT/$TIMESTAMP$SUFFIX"
mkdir -p "$RUN_DIR"

if [[ "$MODE" == "range" ]]; then
  TIME_ARGS="-S $(printf '%q' "$SINCE") -U $(printf '%q' "$UNTIL")"
else
  TIME_ARGS="-S $(printf '%q' "-${WINDOW}min")"
fi

for service in $SERVICES; do
  short="${service%.service}"
  short="${short%-integrated}"
  outfile="$RUN_DIR/${HOST_SHORT}_${short//-/_}_log_${TIMESTAMP}${SUFFIX}.txt"

  # Build one quoted remote command string -- ssh just space-joins separate
  # argv entries without re-quoting them, which would split a "since" value
  # like "2026-07-14 12:00:00" into two words on the remote end.
  remote_cmd="journalctl -u $(printf '%q' "$service") -o short-iso-precise $TIME_ARGS"

  echo "Fetching $service from $(ssh_target "$HOST") -> $outfile"
  if ! ssh "$(ssh_target "$HOST")" "$remote_cmd" > "$outfile"; then
    echo "  WARNING: failed to fetch $service from $HOST" >&2
  fi
done

echo "Done. Logs saved to $RUN_DIR/"
