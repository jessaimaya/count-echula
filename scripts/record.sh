#!/usr/bin/env bash
# Record a window (or a dragged region) with the desktop audio, for the submission video.
#
#   scripts/record.sh            # click the window to record (the `rive game` preview, a browser)
#   scripts/record.sh --region   # drag a rectangle instead
#   scripts/record.sh --fps 30   # default 60
#
# Press q in this terminal to stop. Output: ~/Videos/echula-<time>.mp4
# X11 only (ffmpeg x11grab). Audio is the default output's monitor, so you get the game
# sound, not the microphone. Encodes on the GPU (NVENC) when it can, so the game stays smooth.
set -euo pipefail

FPS=60
MODE=window
while [ $# -gt 0 ]; do
  case "$1" in
    --region) MODE=region ;;
    --fps) FPS="$2"; shift ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

if [ "$MODE" = region ]; then
  echo "Drag a rectangle (right-click cancels)…"
  # --nokeyboard: slop otherwise sees the Enter release that started this script and
  # cancels at once; the short wait lets the key settle
  sleep 0.3
  sel=$(slop --nokeyboard -f "%w %h %x %y") || { echo "Selection cancelled." >&2; exit 1; }
  read -r W H X Y <<<"$sel"
else
  echo "Click the window to record…"
  info=$(xwininfo -frame)
  X=$(sed -n 's/.*Absolute upper-left X: *//p' <<<"$info")
  Y=$(sed -n 's/.*Absolute upper-left Y: *//p' <<<"$info")
  W=$(sed -n 's/.*Width: *//p' <<<"$info")
  H=$(sed -n 's/.*Height: *//p' <<<"$info")
fi
# H.264 needs even sizes
W=$((W / 2 * 2)); H=$((H / 2 * 2))

MONITOR="$(pactl get-default-sink).monitor"
OUT="$HOME/Videos/echula-$(date +%Y%m%d-%H%M%S).mp4"
mkdir -p "$HOME/Videos"

if ffmpeg -hide_banner -loglevel error -f lavfi -i color=s=64x64 -frames:v 1 -c:v h264_nvenc -f null - 2>/dev/null; then
  VIDEO=(-c:v h264_nvenc -preset p5 -rc vbr -cq 19 -b:v 0)
else
  VIDEO=(-c:v libx264 -preset ultrafast -crf 18)
fi

echo "Recording ${W}x${H} at +${X},${Y}, ${FPS} fps, audio from ${MONITOR}"
echo "Press q to stop."
ffmpeg -hide_banner -loglevel warning -stats \
  -thread_queue_size 1024 -f x11grab -framerate "$FPS" -video_size "${W}x${H}" -draw_mouse 1 -i "${DISPLAY:-:0}+${X},${Y}" \
  -thread_queue_size 1024 -f pulse -i "$MONITOR" \
  "${VIDEO[@]}" -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "$OUT"
echo "Saved $OUT"
