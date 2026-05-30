#!/usr/bin/env bash
#
# prep-slack-emoji.sh — the easiest route to a folder of ready-to-upload Slack emoji.
#
# Builds a ./slack-emoji-upload/ folder of correctly-named, Slack-sized emoji from
# open-source packs, ready to drag-and-drop via the "Slack Emoji Tools" browser
# extension (each filename becomes the emoji name).
#
# Packs (set PACKS="..." to choose; default = all four):
#   parrots  Cult of the Party Parrot — 86 animated GIFs. ZERO tools needed.
#   noto     Google Noto Emoji — full Unicode set, Google style. ZERO tools needed.
#            Codepoint filenames are mapped to real shortcodes via emoji_namemap.py.
#   blob     Google "blob" emoji (the beloved deprecated style). ZERO tools needed.
#   fluent   Microsoft Fluent UI Emoji — modern MS style. NEEDS an SVG rasterizer
#            (rsvg-convert or inkscape); auto-skips with an install hint if missing.
#
# General-purpose emoji already exist NATIVELY in Slack, so noto/blob/fluent get a
# style PREFIX (noto_, blob_, fluent_) — otherwise Slack rejects names that collide
# with built-ins. Type :noto_pizza:, :blob_smile:, :fluent_rocket:, :coffeeparrot:.
#
# Usage:
#   ./prep-slack-emoji.sh                         # all packs (fluent if rasterizer present)
#   PACKS="parrots noto" ./prep-slack-emoji.sh    # pick packs
#   PACKS=noto NOTO_PREFIX= ./prep-slack-emoji.sh # no prefix (will clash with natives!)
#   ADD_DIR=~/my-gifs ./prep-slack-emoji.sh       # also fold in your own images
#   OUT_DIR=~/Desktop/emoji ./prep-slack-emoji.sh # change output location
#
# License notes: party parrot core gif = unlimited use (some assets CC-BY-SA 4.0);
# Noto/blob art = Apache-2.0; Fluent = MIT; emoji-data name table = MIT. Attribution
# for CC-BY-SA assets goes in ATTRIBUTION.txt in the output folder.

set -euo pipefail

# ---- config (override via env vars) ----------------------------------------
PACKS="${PACKS:-parrots noto blob fluent}"
WORK_DIR="${WORK_DIR:-$(pwd)/.slack-emoji-src}"   # cache for cloned packs
OUT_DIR="${OUT_DIR:-$(pwd)/slack-emoji-upload}"   # the drag-and-drop folder
ADD_DIR="${ADD_DIR:-}"                            # optional: your own images
MAX_BYTES=131072                                  # Slack hard limit = 128 KB
NOTO_PREFIX="${NOTO_PREFIX-noto_}"                 # prefixes (avoid native clashes)
BLOB_PREFIX="${BLOB_PREFIX-blob_}"
FLUENT_PREFIX="${FLUENT_PREFIX-fluent_}"

PARROT_REPO="https://github.com/jmhobbs/cultofthepartyparrot.com.git"
NOTO_REPO="https://github.com/googlefonts/noto-emoji.git"
BLOB_REPO="https://github.com/tawago/google-emoji-for-slack.git"   # ready blob PNGs
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
RASTERIZER=""; for r in rsvg-convert inkscape; do command -v "$r" >/dev/null && { RASTERIZER="$r"; break; }; done

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

# the MIT name table, fetched once and reused by every codepoint pack.
emoji_json() {
  local j="$WORK_DIR/emoji-data/emoji.json"
  [ -f "$j" ] || { fetch_repo "$EMOJIDATA_REPO" emoji-data emoji.json; }
  printf '%s' "$j"
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

# drop any mapped PNGs that ended up over 128KB (rare for these packs).
trim_oversized_png() {
  local f
  find "$OUT_DIR" -name '*.png' -size +128k -print0 2>/dev/null | while IFS= read -r -d '' f; do
    if command -v pngquant >/dev/null; then
      pngquant --quality=50-90 --force --output "$f" "$f" 2>/dev/null || true
    fi
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

pack_blob() {
  say "blob: fetching Google blob emoji + mapping names"
  fetch_repo "$BLOB_REPO" blob
  local tmp="$WORK_DIR/.blob_flat"; rm -rf "$tmp"; mkdir -p "$tmp"
  find "$WORK_DIR/blob" -type f -name 'emoji_u*.png' -exec cp {} "$tmp/" \;
  python3 "$MAPPER" map --emoji-json "$(emoji_json)" \
    --src "$tmp" --out "$OUT_DIR" --prefix "$BLOB_PREFIX"
}

pack_fluent() {
  if [ -z "$RASTERIZER" ]; then
    warn "fluent: skipped — needs an SVG rasterizer. Install one and re-run:"
    warn "        macOS: brew install librsvg   |   Debian/Ubuntu: apt-get install librsvg2-bin"
    return
  fi
  say "fluent: fetching Microsoft Fluent UI Emoji (rasterizing with $RASTERIZER)"
  fetch_repo "$FLUENT_REPO" fluent assets
  local tmp="$WORK_DIR/.fluent_cp"; rm -rf "$tmp"; mkdir -p "$tmp" n=0
  while IFS=$'\t' read -r cp svg; do
    [ -n "$cp" ] && [ -f "$svg" ] || continue
    if [ "$RASTERIZER" = "rsvg-convert" ]; then
      rsvg-convert -w 128 -h 128 "$svg" -o "$tmp/emoji_u${cp}.png" 2>/dev/null || true
    else
      inkscape "$svg" --export-type=png -w 128 -h 128 -o "$tmp/emoji_u${cp}.png" >/dev/null 2>&1 || true
    fi
  done < <(python3 "$MAPPER" manifest --assets "$WORK_DIR/fluent/assets")
  python3 "$MAPPER" map --emoji-json "$(emoji_json)" \
    --src "$tmp" --out "$OUT_DIR" --prefix "$FLUENT_PREFIX"
}

# ---- run --------------------------------------------------------------------
say "Output folder → $OUT_DIR   (packs: $PACKS)"
rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"

for p in $PACKS; do
  case "$p" in
    parrots) pack_parrots ;;
    noto)    pack_noto ;;
    blob)    pack_blob ;;
    fluent)  pack_fluent ;;
    *) warn "unknown pack '$p' (valid: parrots noto blob fluent)";;
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
  Blob emoji    https://github.com/tawago/google-emoji-for-slack Apache-2.0 / Unlicense
  Fluent Emoji  https://github.com/microsoft/fluentui-emoji      MIT
  Name table    https://github.com/iamcal/emoji-data             MIT
Keep this credit where CC-BY-SA / attribution-required assets are used.
EOF

final=$(find "$OUT_DIR" -type f ! -name ATTRIBUTION.txt | wc -l | tr -d ' ')
echo
ok "Done — $final emoji ready in: $OUT_DIR"
[ "$HAVE_GIFSICLE" -eq 0 ] && warn "gifsicle not installed (only needed if you add oversized GIFs)."
cat <<EOF

Next steps (the easy bulk-upload route):
  1. Install the browser extension "Slack Emoji Tools" (Chrome) /
     "Neutral Face Emoji Tools" (Firefox): https://github.com/takempf/neutral-face-emoji-tools
  2. Open  https://<yourworkspace>.slack.com/customize/emoji
  3. Drag files from  $OUT_DIR  onto the bulk-uploader drop zone (~30-50 at a time).
     Each filename becomes the emoji name.
  4. Try  :coffeeparrot:  :noto_pizza:  :blob_thumbsup:  in any channel 🎉

(Don't upload ATTRIBUTION.txt — it's just the license credit.)
EOF
