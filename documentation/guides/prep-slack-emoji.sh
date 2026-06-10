#!/usr/bin/env bash
#
# prep-slack-emoji.sh — the easiest route to a folder of ready-to-upload Slack emoji.
#
# Builds a ./slack-emoji-upload/ folder of correctly-named, Slack-sized emoji from
# open-source packs, ready to drag-and-drop via the "Slack Emoji Tools" browser
# extension (each filename becomes the emoji name).
#
# Packs (set PACKS="..." to choose; default = parrots noto blobmoji fluent):
#   parrots   Cult of the Party Parrot — 86 animated GIFs.            no extra tools
#   noto      Google Noto Emoji — full Unicode set, Google style.     no extra tools
#   blob      Google "blob" emoji, ~70 ready PNGs (lightweight).      no extra tools
#   blobmoji  FULL blob set (~3,700) rasterized from Blobmoji SVGs.   needs cairosvg*
#   fluent    Microsoft Fluent UI Emoji (~3,100) rasterized.          needs cairosvg*
#
#   * cairosvg is auto-installed via pip on first use (no system packages needed).
#     blob and blobmoji both use the blob_ prefix — pick ONE to avoid duplicates.
#
# General-purpose emoji already exist NATIVELY in Slack, so noto/blob/blobmoji/fluent
# get a style PREFIX (noto_, blob_, fluent_) — otherwise Slack rejects names that
# collide with built-ins. Type :noto_pizza:, :blob_octopus:, :fluent_rocket:, :coffeeparrot:.
#
# Usage:
#   ./prep-slack-emoji.sh                         # default packs
#   PACKS="parrots noto" ./prep-slack-emoji.sh    # pick packs
#   PACKS=noto NOTO_PREFIX= ./prep-slack-emoji.sh # no prefix (will clash with natives!)
#   ADD_DIR=~/my-gifs ./prep-slack-emoji.sh       # also fold in your own images
#   OUT_DIR=~/Desktop/emoji ./prep-slack-emoji.sh # change output location
#
# License notes: party parrot core gif = unlimited use (some assets CC-BY-SA 4.0);
# Noto/blob/Blobmoji art = Apache-2.0; Fluent = MIT; emoji-data name table = MIT.
# Attribution for CC-BY-SA assets goes in ATTRIBUTION.txt in the output folder.

set -euo pipefail

# ---- config (override via env vars) ----------------------------------------
PACKS="${PACKS:-parrots noto blobmoji fluent}"
WORK_DIR="${WORK_DIR:-$(pwd)/.slack-emoji-src}"   # cache for cloned packs
OUT_DIR="${OUT_DIR:-$(pwd)/slack-emoji-upload}"   # the drag-and-drop folder
ADD_DIR="${ADD_DIR:-}"                            # optional: your own images
BATCH_SIZE="${BATCH_SIZE:-500}"                   # split output into batch-NN/ folders (0 = off)
MAX_BYTES=131072                                  # Slack hard limit = 128 KB
NOTO_PREFIX="${NOTO_PREFIX-noto_}"                 # prefixes (avoid native clashes)
BLOB_PREFIX="${BLOB_PREFIX-blob_}"
FLUENT_PREFIX="${FLUENT_PREFIX-fluent_}"

PARROT_REPO="https://github.com/jmhobbs/cultofthepartyparrot.com.git"
NOTO_REPO="https://github.com/googlefonts/noto-emoji.git"
BLOB_REPO="https://github.com/tawago/google-emoji-for-slack.git"   # ready blob PNGs
BLOBMOJI_REPO="https://github.com/C1710/blobmoji.git"             # full blob SVGs
FLUENT_REPO="https://github.com/microsoft/fluentui-emoji.git"
EMOJIDATA_REPO="https://github.com/iamcal/emoji-data.git"          # MIT name table
PARROT_DIRS=(parrots other-parrots guests flags)
# -----------------------------------------------------------------------------

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAPPER="$HERE/emoji_namemap.py"

say()  { printf '\033[1;36m▶ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m⚠ %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }

command -v git     >/dev/null || { echo "git is required."; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required (for name mapping)."; exit 1; }
[ -f "$MAPPER" ] || { echo "missing $MAPPER (keep it next to this script)."; exit 1; }
HAVE_GIFSICLE=0; command -v gifsicle >/dev/null && HAVE_GIFSICLE=1

fsize() { stat -c%s "$1" 2>/dev/null || stat -f%z "$1"; }

# shallow clone or update a repo into $WORK_DIR/<name>; optional sparse path.
fetch_repo() {  # <url> <name> [sparse_subdir]
  local url="$1" name="$2" sparse="${3:-}" dir="$WORK_DIR/$2"
  if [ -d "$dir/.git" ]; then
    git -C "$dir" pull --quiet --ff-only 2>/dev/null || warn "pull failed for $name; using cache"
  elif [ -n "$sparse" ]; then
    git clone --depth 1 --quiet --filter=blob:none --sparse "$url" "$dir"
    git -C "$dir" sparse-checkout set "$sparse"
  else
    git clone --depth 1 --quiet "$url" "$dir"
  fi
}

# the MIT name table, fetched once and reused by every pack.
emoji_json() {
  local j="$WORK_DIR/emoji-data/emoji.json"
  [ -f "$j" ] || fetch_repo "$EMOJIDATA_REPO" emoji-data emoji.json
  printf '%s' "$j"
}

# cairosvg = our portable SVG rasterizer; install it on first use (no system pkgs).
ensure_cairosvg() {
  python3 -c 'import cairosvg' 2>/dev/null && return 0
  say "installing cairosvg (one-time, for SVG packs)…"
  python3 -m pip install --user --quiet cairosvg 2>/dev/null \
    || python3 -m pip install --quiet cairosvg 2>/dev/null || true
  python3 -c 'import cairosvg' 2>/dev/null
}

# copy a GIF to OUT_DIR as <shortcode>.gif, compressing if over the limit.
emit_gif() {
  local src="$1" name dest size i=2
  name="$(basename "${src%.*}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/_/g; s/_+/_/g; s/^_+//; s/_+$//')"
  [ -n "$name" ] || return
  dest="$OUT_DIR/$name.gif"
  while [ -e "$dest" ]; do dest="$OUT_DIR/${name}_${i}.gif"; i=$((i+1)); done
  cp "$src" "$dest"; size=$(fsize "$dest")
  if [ "$size" -gt "$MAX_BYTES" ]; then
    if [ "$HAVE_GIFSICLE" -eq 1 ]; then
      for a in "-O3 --colors=256 --resize-fit 128x128" \
               "-O3 --colors=128 --lossy=40 --resize-fit 128x128" \
               "-O3 --colors=64 --lossy=80 --resize-fit 128x128" \
               "-O3 --colors=32 --lossy=120 --resize-fit 96x96"; do
        gifsicle $a "$dest" -o "$dest.tmp" 2>/dev/null && mv "$dest.tmp" "$dest"
        [ "$(fsize "$dest")" -le "$MAX_BYTES" ] && break
      done
      [ "$(fsize "$dest")" -gt "$MAX_BYTES" ] && { warn "can't fit $(basename "$dest"); removing"; rm -f "$dest"; }
    else
      warn "$(basename "$dest") >128KB and gifsicle missing; removing"; rm -f "$dest"
    fi
  fi
}

# split the flat output into batch-NN/ subfolders of <size> files each, so you can
# drag one folder per upload round. Prints the number of batches created.
batch_split() {
  local size="$1" total n=0 b=0 dir f
  [ "$size" -gt 0 ] 2>/dev/null || { echo 0; return; }
  total=$(find "$OUT_DIR" -maxdepth 1 -type f ! -name ATTRIBUTION.txt | wc -l)
  [ "$total" -gt "$size" ] || { echo 0; return; }   # one batch — leave flat
  while IFS= read -r -d '' f; do
    if [ $((n % size)) -eq 0 ]; then
      b=$((b + 1)); dir="$(printf '%s/batch-%02d' "$OUT_DIR" "$b")"; mkdir -p "$dir"
    fi
    mv "$f" "$dir/"; n=$((n + 1))
  done < <(find "$OUT_DIR" -maxdepth 1 -type f ! -name ATTRIBUTION.txt -print0 | sort -z)
  echo "$b"
}

# drop/shrink any mapped PNGs that ended up over 128KB (rare at 128px).
trim_oversized_png() {
  local f
  find "$OUT_DIR" -type f -name '*.png' -size +128k -print0 2>/dev/null | while IFS= read -r -d '' f; do
    command -v pngquant >/dev/null && pngquant --quality=50-90 --force --output "$f" "$f" 2>/dev/null || true
    [ "$(fsize "$f")" -gt "$MAX_BYTES" ] && { warn "$(basename "$f") >128KB; removing"; rm -f "$f"; }
  done
}

# ---- pack builders ----------------------------------------------------------
pack_parrots() {
  say "parrots: fetching Cult of the Party Parrot"
  fetch_repo "$PARROT_REPO" parrots
  local d
  for d in "${PARROT_DIRS[@]}"; do
    [ -d "$WORK_DIR/parrots/$d" ] || continue
    while IFS= read -r -d '' f; do emit_gif "$f"; done \
      < <(find "$WORK_DIR/parrots/$d" -maxdepth 1 -type f -name '*.gif' -print0)
  done
}

pack_noto() {
  say "noto: fetching Google Noto Emoji + mapping names"
  fetch_repo "$NOTO_REPO" noto png/128
  python3 "$MAPPER" map --emoji-json "$(emoji_json)" \
    --src "$WORK_DIR/noto/png/128" --out "$OUT_DIR" --prefix "$NOTO_PREFIX"
}

pack_blob() {  # lightweight, ready-made PNGs, no rasterizer
  say "blob: fetching Google blob emoji (ready PNGs) + mapping names"
  fetch_repo "$BLOB_REPO" blob
  local tmp="$WORK_DIR/.blob_flat"; rm -rf "$tmp"; mkdir -p "$tmp"
  find "$WORK_DIR/blob" -type f -name 'emoji_u*.png' -exec cp {} "$tmp/" \;
  python3 "$MAPPER" map --emoji-json "$(emoji_json)" \
    --src "$tmp" --out "$OUT_DIR" --prefix "$BLOB_PREFIX"
}

pack_blobmoji() {  # full blob set, rasterized from SVG
  if ! ensure_cairosvg; then
    warn "blobmoji: skipped — cairosvg unavailable. Install: python3 -m pip install --user cairosvg"
    return
  fi
  say "blobmoji: fetching + rasterizing FULL blob set (~3,700 svg, takes a minute)"
  fetch_repo "$BLOBMOJI_REPO" blobmoji svg
  local png="$WORK_DIR/.blobmoji_png"; rm -rf "$png"
  python3 "$MAPPER" rasterize --svg-dir "$WORK_DIR/blobmoji/svg" --out "$png"
  python3 "$MAPPER" map --emoji-json "$(emoji_json)" \
    --src "$png" --out "$OUT_DIR" --prefix "$BLOB_PREFIX"
}

pack_fluent() {  # Microsoft Fluent, rasterized from SVG
  if ! ensure_cairosvg; then
    warn "fluent: skipped — cairosvg unavailable. Install: python3 -m pip install --user cairosvg"
    return
  fi
  say "fluent: fetching + rasterizing Microsoft Fluent UI (~3,100 svg, takes a minute)"
  fetch_repo "$FLUENT_REPO" fluent assets
  local png="$WORK_DIR/.fluent_png"; rm -rf "$png"
  python3 "$MAPPER" rasterize --fluent-assets "$WORK_DIR/fluent/assets" --out "$png"
  python3 "$MAPPER" map --emoji-json "$(emoji_json)" \
    --src "$png" --out "$OUT_DIR" --prefix "$FLUENT_PREFIX"
}

# ---- run --------------------------------------------------------------------
say "Output folder → $OUT_DIR   (packs: $PACKS)"
rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"

for p in $PACKS; do
  case "$p" in
    parrots)  pack_parrots ;;
    noto)     pack_noto ;;
    blob)     pack_blob ;;
    blobmoji) pack_blobmoji ;;
    fluent)   pack_fluent ;;
    *) warn "unknown pack '$p' (valid: parrots noto blob blobmoji fluent)";;
  esac
done

# optional: your own images
if [ -n "$ADD_DIR" ] && [ -d "$ADD_DIR" ]; then
  say "Adding your own images from $ADD_DIR"
  while IFS= read -r -d '' f; do
    case "${f,,}" in *.gif) emit_gif "$f";; *.png|*.jpg|*.jpeg) cp "$f" "$OUT_DIR/";; esac
  done < <(find "$ADD_DIR" -maxdepth 1 -type f \( -iname '*.gif' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -print0)
fi

trim_oversized_png

cat > "$OUT_DIR/ATTRIBUTION.txt" <<EOF
Emoji sources & licenses:
  Party Parrot  https://cultofthepartyparrot.com   core gif: unlimited use; some assets CC-BY-SA 4.0
  Noto Emoji    https://github.com/googlefonts/noto-emoji        Apache-2.0
  Blob (lite)   https://github.com/tawago/google-emoji-for-slack Apache-2.0 / Unlicense
  Blobmoji      https://github.com/C1710/blobmoji                Apache-2.0 (images) / OFL (font)
  Fluent Emoji  https://github.com/microsoft/fluentui-emoji      MIT
  Name table    https://github.com/iamcal/emoji-data             MIT
Keep this credit where CC-BY-SA / attribution-required assets are used.
EOF

final=$(find "$OUT_DIR" -type f ! -name ATTRIBUTION.txt | wc -l | tr -d ' ')
batches=$(batch_split "$BATCH_SIZE")
echo
ok "Done — $final emoji ready in: $OUT_DIR"
[ "$HAVE_GIFSICLE" -eq 0 ] && warn "gifsicle not installed (only needed if you add oversized GIFs)."

if [ "$batches" -gt 0 ]; then
  ok "Split into $batches folders of up to $BATCH_SIZE: $OUT_DIR/batch-01 … batch-$(printf '%02d' "$batches")"
  drag_hint="Drag the contents of one  batch-NN/  folder per upload round (each = up to $BATCH_SIZE emoji)."
else
  drag_hint="Drag files from  $OUT_DIR  onto the drop zone (~30-50 at a time)."
fi

cat <<EOF

Next steps (the easy bulk-upload route):
  1. Install the browser extension "Slack Emoji Tools" (Chrome) /
     "Neutral Face Emoji Tools" (Firefox): https://github.com/takempf/neutral-face-emoji-tools
  2. Open  https://<yourworkspace>.slack.com/customize/emoji
  3. $drag_hint
     Each filename becomes the emoji name.
  4. Try  :coffeeparrot:  :noto_pizza:  :blob_octopus:  :fluent_rocket:  in any channel 🎉

(Don't upload ATTRIBUTION.txt — it's just the license credit.)
EOF
