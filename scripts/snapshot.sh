#!/bin/zsh
# Captures every state of the built app to PNGs for visual checking.
#
#   AINOTCH_SHOW_NOTCH=1 ./scripts/snapshot.sh [outdir]
#
# AINOTCH_SHOW_NOTCH=1 matters: a screenshot never contains the hardware notch,
# so without it a value hidden behind the notch looks correctly placed. Set
# AINOTCH_FAKE_NOTCH_WIDTH / _HEIGHT to check another display mode's geometry.
#
# This launches the app bundle, not the bare SwiftPM binary: the bare binary
# reads a different preferences domain and so shows a different layout.
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
OUT_DIR=${1:-"$PROJECT_DIR/dist/snapshots"}
BINARY="$PROJECT_DIR/dist/AI Notch.app/Contents/MacOS/AINotch"
LOG=$(mktemp -t ainotch-snapshot)

"$PROJECT_DIR/scripts/build-app.sh" >/dev/null
mkdir -p "$OUT_DIR"

WAS_RUNNING=0
if pgrep -x AINotch >/dev/null; then WAS_RUNNING=1; fi

# name, window-id key printed by the app, then the environment for that state
capture() {
  local name=$1 key=$2
  shift 2
  pkill -x AINotch 2>/dev/null || true
  sleep 0.5
  : > "$LOG"
  # AINOTCH_CAPTURE makes the panel ignore the pointer, so using the Mac
  # during a run cannot change what gets photographed.
  env AINOTCH_PRINT_WINDOW_ID=1 AINOTCH_CAPTURE=1 "$@" "$BINARY" 2>"$LOG" &
  local pid=$!

  local id=""
  for _ in {1..40}; do
    id=$(sed -n "s/^${key}=//p" "$LOG" | tail -1)
    [[ -n "$id" ]] && break
    sleep 0.25
  done
  if [[ -z "$id" ]]; then
    kill $pid 2>/dev/null || true
    echo "FAILED $name: the app never reported $key" >&2
    return 1
  fi

  # Long enough for the first scan to land, so figures are real, not "–".
  sleep 6
  # Never leave a capture-mode app running: its panel ignores the pointer.
  local rc=0
  screencapture -x -o -l"$id" "$OUT_DIR/$name.png" || rc=$?
  kill $pid 2>/dev/null || true
  wait $pid 2>/dev/null || true
  if (( rc != 0 )); then
    echo "FAILED $name: the window closed before it could be captured" >&2
    return 1
  fi
  echo "$OUT_DIR/$name.png"
}

capture collapsed WINDOW_ID
capture widgets   WINDOW_ID AINOTCH_PREVIEW=1 AINOTCH_PREVIEW_TAB=widgets
capture graph     WINDOW_ID AINOTCH_PREVIEW=1 AINOTCH_PREVIEW_TAB=graph
capture graph-30d WINDOW_ID AINOTCH_PREVIEW=1 AINOTCH_PREVIEW_TAB=graph AINOTCH_PREVIEW_RANGE=thirtyDays
capture graph-all WINDOW_ID AINOTCH_PREVIEW=1 AINOTCH_PREVIEW_TAB=graph AINOTCH_PREVIEW_RANGE=all
capture heatmap     WINDOW_ID AINOTCH_PREVIEW=1 AINOTCH_PREVIEW_TAB=graph AINOTCH_PREVIEW_GRAPH=heatmap
capture heatmap-30d WINDOW_ID AINOTCH_PREVIEW=1 AINOTCH_PREVIEW_TAB=graph AINOTCH_PREVIEW_GRAPH=heatmap AINOTCH_PREVIEW_RANGE=thirtyDays
capture heatmap-all WINDOW_ID AINOTCH_PREVIEW=1 AINOTCH_PREVIEW_TAB=graph AINOTCH_PREVIEW_GRAPH=heatmap AINOTCH_PREVIEW_RANGE=all
capture settings  WINDOW_ID AINOTCH_PREVIEW=1 AINOTCH_PREVIEW_TAB=quick
capture customize CUSTOMIZATION_WINDOW_ID AINOTCH_PREVIEW_CUSTOMIZE=1

rm -f "$LOG"
# Relaunch without this script's AINOTCH_* settings. `open` hands the caller's
# environment to the app, so AINOTCH_SHOW_NOTCH=1 once followed the everyday
# app home and left the pink capture silhouette painted over the real notch.
if (( WAS_RUNNING )); then
  env $(env | sed -n 's/^\(AINOTCH_[A-Z_]*\)=.*/-u \1/p') open "$PROJECT_DIR/dist/AI Notch.app"
fi
