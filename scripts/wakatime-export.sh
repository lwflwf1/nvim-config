#!/bin/bash
# wakatime-export.sh - RHEL6 side of the wakapi mail bridge.
#
# The air-gapped box cannot reach wakapi, so its heartbeat queue is mailed out
# instead: dump the local bbolt queue to JSON, pack+compress it with ferry,
# mail the (<=1 MiB) parts, then clear the queue. The receiving end is
# `ferry recv` + `:WakaSync` on a networked machine.
#
# All of the export logic lives here on purpose, and Lua (:WakaExport) only runs
# this file: the queue must stay rescuable even when nvim cannot start on this
# box. The sync side has no such requirement -- it runs on a machine with
# network and a working editor -- so it lives in lua/box/wakatime.lua.
#
# Why JSON and not the .bdb: bbolt copy-on-writes and nothing in wakatime-cli
# ever compacts it, so the file only grows and never shrinks -- the moment it
# passes 1 MiB (this box's per-file mail limit) copying it is impossible. JSON
# also compresses ~5-20x, so one part carries far more heartbeats.
#
# Why the queue is cleared: --print-offline-heartbeats always dumps the WHOLE
# queue, so leaving it would re-send everything on the next run and the queue
# would grow without bound until the archive blew past ferry's 10 MiB prompt
# (which cancels instead of splitting in a non-interactive run). Clearing it on
# success is safe because by then the parts are in the mailbox, and the receiver
# does not delete a message until it has been uploaded to wakapi -- at every
# instant the data lives in at least one place.
#
# IMPORTANT: do not edit files while this runs. The queue is deleted on success,
# so a heartbeat appended between the dump and the delete would go with it. The
# script warns when a wakatime-cli process is currently running.
#
# Usage: wakatime-export.sh [-n|--keep-queue] [-d DIR] [-t RECIPIENT]
#   -n  keep the queue (and the local artifacts) after a successful send
#   -d  working directory for the .json/.zip (default: ~/wakatime-ferry)
#   -t  recipient (default: "$(id -un)@asrmicro.com")
#
# Env overrides: FERRY (a command name or a path, tried as-is; unset -> resolved
# by resolve_ferry()), WAKATIME_HOME.
set -uo pipefail

OUT_DIR="${HOME}/wakatime-ferry"
RECIPIENT="$(id -un)@asrmicro.com"
KEEP_Q=0
FERRY="${FERRY:-}"   # empty -> resolved in preflight, see resolve_ferry()

while getopts "nd:t:" opt; do
    case "$opt" in
        n) KEEP_Q=1 ;;
        d) OUT_DIR="$OPTARG" ;;
        t) RECIPIENT="$OPTARG" ;;
        *) echo "usage: $0 [-n] [-d DIR] [-t RECIPIENT]" >&2; exit 2 ;;
    esac
done

WK_HOME="${WAKATIME_HOME:-$HOME}"
CLI="$WK_HOME/.wakatime/wakatime-cli"
QUEUE="$WK_HOME/.wakatime/offline_heartbeats.bdb"

log()  { printf '%s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
# ferry is installed on this box as ~/.local/bin/ferry.py: there is no bare
# `ferry` command, so resolving only that name fails even though ferry is right
# there. Try the .py spelling, the bare name (some installs add a wrapper), and
# the install location, in that order. An explicit FERRY wins and is never
# second-guessed -- it may be a wrapper script with its own interpreter.
resolve_ferry() {
    if [ -n "$FERRY" ]; then
        command -v "$FERRY" >/dev/null 2>&1 && return 0
        return 1
    fi
    for cand in ferry.py ferry "$HOME/.local/bin/ferry.py" "$HOME/.local/bin/ferry"; do
        if command -v "$cand" >/dev/null 2>&1; then
            FERRY="$cand"
            return 0
        fi
    done
    return 1
}

resolve_ferry || die "ferry not found (tried: \$FERRY, ferry.py, ferry, ~/.local/bin/ferry.py)
       set FERRY=/path/to/ferry.py, or make one of those names work"
log "ferry: $(command -v "$FERRY")"

# `command -v` only proves the file exists. A Python too old for ferry's syntax,
# or a shebang pointing at the wrong interpreter, makes every subcommand die
# before doing anything -- which surfaced as a traceback from `ferry pack` deep
# in the run, after the queue had already been dumped. `--help` is the cheapest
# call that proves the interpreter can load and parse it (ferry has no
# --version); it does not prove anything about ssl, which pack/email no longer
# need and which therefore cannot break them.
"$FERRY" --help >/dev/null 2>&1 || die "ferry found at $FERRY but it will not run:
       $("$FERRY" --help 2>&1 | tail -n 3 | sed 's/^/       /')
       (it is a python3 script -- check python3 --version)"
[ -x "$CLI" ] || die "wakatime-cli not executable: $CLI
       run the offline installer (it links ~/.local/bin/wakatime-cli-linux-amd64)"

if command -v pgrep >/dev/null 2>&1 && pgrep -f 'wakatime-cli' >/dev/null 2>&1; then
    warn "a wakatime-cli process is running right now"
    warn "if you are editing, a heartbeat written during this export can be lost with the queue"
fi

[ -f "$QUEUE" ] || die "no offline queue at $QUEUE
       (it appears once wakatime-cli has recorded a heartbeat)"

COUNT="$("$CLI" --offline-queue-file "$QUEUE" --offline-count 2>/dev/null | tr -d '\r\n')"
case "$COUNT" in
    ''|*[!0-9]*) die "unexpected --offline-count output: '$COUNT' (is the queue corrupt?)" ;;
esac
if [ "$COUNT" = 0 ]; then
    log "offline queue is empty - nothing to export"
    exit 0
fi
log "queued heartbeats: $COUNT"

# Only create the working dir once there is actually something to export.
mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
# ---------------------------------------------------------------- dump
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="wakatime-${STAMP}.zip"
JSON="$OUT_DIR/wakatime-${STAMP}.json"

log "dumping to $(basename "$JSON")"
"$CLI" --offline-queue-file "$QUEUE" --print-offline-heartbeats "$COUNT" > "$JSON" \
    || die "failed to dump the queue"
[ -s "$JSON" ] || die "the dump is empty (pass N=0? note --print-offline-heartbeats 0 prints NOTHING: ReadMany stops at len >= limit)"

# Re-read the dump and compare with the queue's own count: the dump is now the
# only copy that will travel, so a short write must not be sent as if complete.
DUMPED="$(python3 -c '
import json,sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception as e:
    sys.stderr.write("%s\n" % e); sys.exit(2)
print(len(d))
' "$JSON")" || die "the dump is not valid JSON: $JSON"
if [ "$DUMPED" != "$COUNT" ]; then
    die "dump holds $DUMPED heartbeats but the queue reported $COUNT - refusing to send"
fi
log "dumped $DUMPED heartbeats ($(wc -c < "$JSON" | tr -d ' ') bytes)"

# ---------------------------------------------------------------- pack
# ferry's pack records paths relative to Path.cwd(), so the input has to be
# inside it -- hence running ferry with cwd = the export dir and -i a basename.
log "packing with ferry (cwd=$OUT_DIR)"
( cd "$OUT_DIR" && "$FERRY" pack -i "$(basename "$JSON")" -o "$ARCHIVE" -f zip ) \
    || { warn "ferry pack failed"; exit 1; }

ZIP_PATH="$OUT_DIR/$ARCHIVE"
[ -f "$ZIP_PATH" ] || die "ferry did not produce $ZIP_PATH"
ZIP_SIZE="$(wc -c < "$ZIP_PATH" | tr -d ' ')"
PARTS=$(( (ZIP_SIZE + 1048575) / 1048576 ))
log "archive: $(basename "$ZIP_PATH") ${ZIP_SIZE} bytes -> ${PARTS} mail part(s) at 1 MiB"

if [ "$ZIP_SIZE" -gt 10485760 ]; then
    die "archive is $(( ZIP_SIZE / 1048576 )) MiB; ferry prompts above 10 MiB and CANCELS
       in a non-interactive run. Export more often, or raise its FILE_SIZE_LIMIT.
       (the .json and .zip were left in $OUT_DIR)"
fi

# ---------------------------------------------------------------- send
# ferry splits at exactly 1 MiB (its SPLIT_SIZE), mails one message per part
# with subject "Directory Archive: <archive> [i/N]", then deletes the parts.
# Its `email` subcommand reports failure via the exit code, unlike `pack -e`
# which swallows send_email()'s result -- so send as a separate step.
log "mailing to $RECIPIENT"
if ! ( cd "$OUT_DIR" && "$FERRY" email -i "$ARCHIVE" -t "$RECIPIENT" ); then
    warn "ferry email failed - nothing was cleaned up, fix and re-run"
    warn "artifacts kept: $JSON  $ZIP_PATH"
    exit 1
fi

# ---------------------------------------------------------------- cleanup
# By now every part is in the mailbox, so the local copies can go. But before
# dropping the queue, re-read it: a heartbeat appended while the mail was being
# sent lives in the same file, and deleting it would lose a heartbeat the dump
# never captured. Keeping the queue in that case costs a re-send next time
# (wakapi dedupes by hash) and loses nothing.
if [ "$KEEP_Q" = 0 ]; then
    AFTER="$("$CLI" --offline-queue-file "$QUEUE" --offline-count 2>/dev/null | tr -d '\r\n')"
    case "$AFTER" in
        ''|*[!0-9]*) AFTER="$COUNT" ;;
    esac
    if [ "$AFTER" != "$COUNT" ]; then
        warn "queue grew from $COUNT to $AFTER while this ran - keeping it"
        warn "the extra heartbeat(s) are newer than the dump; next export re-sends"
        warn "the whole queue, and wakapi dedupes by hash, so nothing is lost"
        KEEP_Q=1
    fi
fi

if [ "$KEEP_Q" = 1 ]; then
    log "keeping the local artifacts and the queue (--keep-queue):"
    log "  $JSON"
    log "  $ZIP_PATH"
    log "  $QUEUE"
    log "NOTE: the next export will re-send these heartbeats (server-side hash dedup"
    log "      makes that harmless but wasteful)"
else
    # The parts are in the mailbox and the receiver will not delete them until
    # they are uploaded, so dropping the local copies loses nothing. Clearing
    # the queue is what keeps the next export to just the new heartbeats; it is
    # recreated on the next heartbeat.
    rm -f "$JSON" "$ZIP_PATH"
    rm -f "$QUEUE"
    log "cleaned up the local artifacts and cleared the queue: $QUEUE"
fi

log ""
log "done: $COUNT heartbeats mailed in ${PARTS} part(s) to $RECIPIENT"
log "next, on a machine that can reach the internet, in nvim:"
log "  :WakaSync    # ferry recv -> merge -> unpack -> POST to wakapi"
log "or just the download half, by hand:"
log "  ferry recv -c imap.json -o ~/wakatime-ferry/incoming -s 'Directory Archive: wakatime-'"
