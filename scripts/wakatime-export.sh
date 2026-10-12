#!/bin/bash
# Export the RHEL6 wakatime-cli offline queue for manual transfer.
#
# RHEL6 is air-gapped, so heartbeats accumulate in the local bbolt queue
# (~/.wakatime/offline_heartbeats.bdb) instead of being uploaded. This copies
# that queue out; scripts/wakatime-sync.ps1 replays it on a networked machine.
#
# Usage: wakatime-export.sh [-o OUTDIR] [-q]
#          -o OUTDIR  where to write the .bdb (default: ./wakatime-export)
#          -q         quiet; only print the file path and sha256
#
# IMPORTANT: close every nvim instance first. bbolt takes an exclusive flock and
# writes copy-on-write pages, so copying the file while the CLI has it open can
# capture a torn database. The post-copy --offline-count below is the safety net:
# a torn copy fails to open and we abort before anything is lost.
set -u

OUT_DIR="./wakatime-export"
QUIET=0
while getopts "o:q" opt; do
    case "$opt" in
        o) OUT_DIR="$OPTARG" ;;
        q) QUIET=1 ;;
        *) echo "usage: $0 [-o OUTDIR] [-q]" >&2; exit 2 ;;
    esac
done

HOME_DIR="${WAKATIME_HOME:-$HOME}"
CLI="$HOME_DIR/.wakatime/wakatime-cli"
QUEUE="$HOME_DIR/.wakatime/offline_heartbeats.bdb"

log() { [ "$QUIET" = 1 ] || echo "$*"; }
die() { echo "$*" >&2; exit 1; }

[ -x "$CLI" ] || die "wakatime-cli not executable: $CLI
  (expected a symlink to ~/.local/bin/wakatime-cli-linux-amd64, created by
   box.wakatime.bootstrap(); if missing, run the offline installer)"

if [ ! -f "$QUEUE" ]; then
    log "no offline queue yet: $QUEUE"
    log "(it only appears once wakatime-cli has failed to upload a heartbeat)"
    exit 0
fi

mkdir -p "$OUT_DIR" || die "cannot create $OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
DEST="$OUT_DIR/wakatime-$STAMP.bdb"

COUNT="$("$CLI" --offline-queue-file "$QUEUE" --offline-count 2>&1)" \
    || die "cannot read the queue (is nvim still running?): $COUNT"
[ -n "$COUNT" ] || die "unexpected empty --offline-count output"

SIZE="$(wc -c < "$QUEUE" | tr -d ' ')"

if [ "$COUNT" = "0" ]; then
    log "offline queue is empty ($SIZE bytes) -- nothing to export"
    exit 0
fi

if [ "$SIZE" -gt 1048576 ]; then
    log "WARNING: queue is $SIZE bytes (>1 MiB). If your transfer only allows"
    log "         1 MiB per trip, export more often, or compress the JSON dump:"
    log "           $CLI --print-offline-heartbeats $COUNT --offline-queue-file $QUEUE | gzip -9 > $DEST.json.gz"
fi

cp -f "$QUEUE" "$DEST" || die "copy failed"
chmod 0600 "$DEST"

# Integrity check on the *copy*: only now do we know it is readable, so a torn
# file can never be mistaken for a good export.
VERIFY="$("$CLI" --offline-queue-file "$DEST" --offline-count 2>&1)" \
    || die "the exported copy is unreadable (db was being written?) -- aborting: $VERIFY"
[ "$VERIFY" = "$COUNT" ] \
    || die "copy holds $VERIFY heartbeats but the source had $COUNT -- aborting"

SUM="$(sha256sum "$DEST" | cut -d' ' -f1)"

log "heartbeats : $COUNT"
log "source     : $QUEUE ($SIZE bytes)"
log "exported   : $DEST"
if [ "$QUIET" = 1 ]; then
    echo "$DEST"
else
    log "sha256     : $SUM"
    log ""
    log "Copy $DEST to a networked machine and run:"
    log "  pwsh -File scripts/wakatime-sync.ps1 -QueueFile <copied .bdb>"
fi
