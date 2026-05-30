#!/usr/bin/env bash
#
# prep-slack-emoji.sh — the easiest route to a folder of ready-to-upload Slack emoji.
#
# What it does:
#   1. Downloads the iconic, permissively-licensed "Cult of the Party Parrot" pack
#      (86 animated GIFs — parrots + blob/guest reactions).
#   2. Sanitizes every filename into a valid Slack shortcode (lowercase, underscores).
#   3. Ensures every file is under Slack's 128 KB limit. The standard-res parrots
#      already are, so NO image tools are needed for the default pack. If a file is
#      ever too big (e.g. you drop your own GIFs into ADD_DIR), it auto-compresses
#      with gifsicle when available.
#   4. Puts everything in ./slack-emoji-upload/ — ready to drag-and-drop.
#
# Then: install the "Slack Emoji Tools" / "Neutral Face Emoji Tools" browser
# extension, open https://<yourworkspace>.slack.com/customize/emoji, and drag the
# whole folder onto the bulk uploader. Each filename becomes the emoji name.
#
# Usage:
#   ./prep-slack-emoji.sh              # default: download + prep the party parrot pack
#   ADD_DIR=~/my-gifs ./prep-slack-emoji.sh   # also include your own images
#   OUT_DIR=~/Desktop/emoji ./prep-slack-emoji.sh   # change output location
#
# License notes: the core party parrot gif is granted for unlimited use; some assets
# are CC-BY-SA 4.0 (attribution + sharealike) and Apache-2.0. Keep a credit line for
# CC-BY-SA assets. See the upstream LICENSE in the cloned repo.

set -euo pipefail

# ---- config (override via env vars) ----------------------------------------
REPO_URL="https://github.com/jmhobbs/cultofthepartyparrot.com.git"
WORK_DIR="${WORK_DIR:-$(pwd)/.slack-emoji-src}"   # where the pack is cloned
OUT_DIR="${OUT_DIR:-$(pwd)/slack-emoji-upload}"   # the drag-and-drop folder
ADD_DIR="${ADD_DIR:-}"                            # optional: your own images folder
MAX_BYTES=131072                                  # Slack hard limit = 128 KB
# Folders inside the pack to harvest standard-res (already Slack-sized) GIFs from:
PACK_DIRS=(parrots other-parrots guests flags)
# -----------------------------------------------------------------------------

say()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }

command -v git  >/dev/null || { echo "git is required. Install git and re-run."; exit 1; }
HAVE_GIFSICLE=0; command -v gifsicle >/dev/null && HAVE_GIFSICLE=1

# Turn any filename into a safe Slack shortcode: lowercase, only [a-z0-9_],
# collapse repeats, trim leading/trailing underscores.
shortcode() {
  local base="${1%.*}"
  base="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9]+/_/g; s/_+/_/g; s/^_+//; s/_+$//')"
  printf '%s' "$base"
}

# file size in bytes, portable across linux/macOS
fsize() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1"; }

# Copy a GIF into OUT_DIR under <shortcode>.<ext>, compressing if over the limit.
emit() {
  local src="$1" ext="${1##*.}" name dest size
  name="$(shortcode "$(basename "$src")")"
  [ -n "$name" ] || { warn "skipping unnameable file: $src"; return; }
  dest="$OUT_DIR/$name.${ext,,}"

  # de-dupe name collisions
  local i=2
  while [ -e "$dest" ]; do dest="$OUT_DIR/${name}_${i}.${ext,,}"; i=$((i+1)); done

  cp "$src" "$dest"
  size=$(fsize "$dest")
  if [ "$size" -gt "$MAX_BYTES" ]; then
    if [ "${ext,,}" = "gif" ] && [ "$HAVE_GIFSICLE" -eq 1 ]; then
      # progressively harder compression until it fits
      for args in \
        "-O3 --colors=256 --resize-fit 128x128" \
        "-O3 --colors=128 --lossy=40 --resize-fit 128x128" \
        "-O3 --colors=64  --lossy=80 --resize-fit 128x128" \
        "-O3 --colors=32  --lossy=120 --resize-fit 96x96"; do
        gifsicle $args "$dest" -o "$dest.tmp" 2>/dev/null && mv "$dest.tmp" "$dest"
        [ "$(fsize "$dest")" -le "$MAX_BYTES" ] && break
      done
      if [ "$(fsize "$dest")" -gt "$MAX_BYTES" ]; then
        warn "could not get $(basename "$dest") under 128KB — removing"; rm -f "$dest"
      fi
    else
      warn "$(basename "$dest") is $((size/1024))KB (>128KB) and can't compress (need gifsicle) — removing"
      rm -f "$dest"
    fi
  fi
}

# ---- 1. get the pack --------------------------------------------------------
if [ -d "$WORK_DIR/.git" ]; then
  say "Updating existing pack in $WORK_DIR"
  git -C "$WORK_DIR" pull --quiet --ff-only || warn "pull failed; using existing copy"
else
  say "Downloading party parrot pack → $WORK_DIR"
  git clone --depth 1 --quiet "$REPO_URL" "$WORK_DIR"
fi

# ---- 2. prep output ---------------------------------------------------------
say "Building drag-and-drop folder → $OUT_DIR"
rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"

count=0
for d in "${PACK_DIRS[@]}"; do
  [ -d "$WORK_DIR/$d" ] || continue
  while IFS= read -r -d '' f; do emit "$f"; count=$((count+1)); done \
    < <(find "$WORK_DIR/$d" -maxdepth 1 -type f -name '*.gif' -print0)
done

# ---- 3. optional: include your own images ----------------------------------
if [ -n "$ADD_DIR" ] && [ -d "$ADD_DIR" ]; then
  say "Adding your own images from $ADD_DIR"
  while IFS= read -r -d '' f; do emit "$f"; count=$((count+1)); done \
    < <(find "$ADD_DIR" -maxdepth 1 -type f \( -iname '*.gif' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print0)
fi

final=$(find "$OUT_DIR" -type f | wc -l | tr -d ' ')

# ---- 4. attribution note ----------------------------------------------------
cat > "$OUT_DIR/ATTRIBUTION.txt" <<EOF
These emoji come from Cult of the Party Parrot (https://cultofthepartyparrot.com).
Core party parrot gif: granted for unlimited use. Some assets are CC-BY-SA 4.0 and
Apache-2.0 — keep this credit when using them. Full terms: $WORK_DIR/LICENSE
EOF

echo
ok "Done — $final emoji ready in: $OUT_DIR"
[ "$HAVE_GIFSICLE" -eq 0 ] && warn "gifsicle not installed (not needed for the default pack; install it only if you add oversized GIFs: 'brew install gifsicle' / 'apt-get install gifsicle')."
cat <<EOF

Next steps (the easy bulk-upload route):
  1. Install the browser extension "Slack Emoji Tools" (Chrome) /
     "Neutral Face Emoji Tools" (Firefox).
       https://github.com/takempf/neutral-face-emoji-tools
  2. Open  https://<yourworkspace>.slack.com/customize/emoji
  3. Drag the files from  $OUT_DIR  onto the bulk-uploader drop zone.
     (Do ~30-50 at a time. Each filename becomes the emoji name.)
  4. Done — try typing :coffeeparrot: in any channel 🎉

(ATTRIBUTION.txt is in the folder; don't upload it — it's just the license credit.)
EOF
