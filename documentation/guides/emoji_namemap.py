#!/usr/bin/env python3
"""emoji_namemap.py — map/rasterize open-source emoji into Slack shortcodes.

Open packs name files inconsistently: by Unicode codepoint
(``emoji_u1f600.png``), by description (``grinning face.svg``), or buried in
per-emoji folders (Microsoft Fluent). This tool normalises all of that into
clean Slack shortcodes (``grinning.png``) using the MIT-licensed
``iamcal/emoji-data`` name table — the same lineage Slack uses, so codes feel native.

Standard library only, EXCEPT the optional ``rasterize`` command which needs
``cairosvg`` (pip-installable; pure-python-ish, no system packages).

Subcommands:
  map        Copy <src>/*.png -> <out>/<prefix><shortcode>.png. Codepoint names
             (emoji_u*.png) use the name table; other names are sanitized as-is.
  rasterize  Turn SVGs into 128x128 PNGs (for `map`) using cairosvg. Either a flat
             --svg-dir, or Microsoft Fluent's --fluent-assets tree.
"""
import argparse
import json
import os
import re
import shutil
import sys

SKIN_TONES = {
    "1F3FB": "light_skin", "1F3FC": "medium_light_skin", "1F3FD": "medium_skin",
    "1F3FE": "medium_dark_skin", "1F3FF": "dark_skin",
}
IGNORE_CP = {"FE0F"}  # variation selector — strip before matching


def norm_key(codepoints):
    """Uppercase, drop FE0F, join with '-' -> canonical match key."""
    return "-".join(cp.upper() for cp in codepoints if cp.upper() not in IGNORE_CP)


def sanitize(name):
    """Force a string into a valid Slack shortcode: [a-z0-9_]."""
    name = re.sub(r"[^a-z0-9]+", "_", name.lower())
    return re.sub(r"_+", "_", name).strip("_")


def best_short(rec):
    """Pick the friendliest shortcode for a record (prefer word-like aliases)."""
    candidates = list(rec.get("short_names") or [])
    primary = rec.get("short_name")
    if primary and primary not in candidates:
        candidates = [primary] + candidates
    cleaned = [(c, sanitize(c)) for c in candidates]
    cleaned = [(orig, s) for orig, s in cleaned if s]
    if not cleaned:
        return None
    for _orig, s in cleaned:
        if s[0].isalpha():
            return s
    return cleaned[0][1]


def build_map(emoji_json_path):
    """Return {canonical-codepoint-key: shortcode} from emoji-data."""
    with open(emoji_json_path, encoding="utf-8") as fh:
        data = json.load(fh)
    table = {}

    def add(unified, short):
        if not unified or not short:
            return
        table.setdefault(norm_key(unified.split("-")), sanitize(short))

    for rec in data:
        short = best_short(rec)
        add(rec.get("unified"), short)
        add(rec.get("non_qualified"), short)
        for variant in (rec.get("skin_variations") or {}).values():
            for field in ("unified", "non_qualified"):
                uni = variant.get(field)
                if not uni:
                    continue
                cps = [c for c in uni.split("-") if c.upper() not in IGNORE_CP]
                tones = [SKIN_TONES[c.upper()] for c in cps if c.upper() in SKIN_TONES]
                add(uni, f"{short}_{'_'.join(tones) if tones else 'tone'}")
    return table


FNAME_RE = re.compile(r"^emoji_u([0-9a-fA-F_]+)$")


def shortcode_for(stem, table):
    """Codepoint stem -> table lookup; otherwise sanitize the descriptive name."""
    m = FNAME_RE.match(stem)
    if m:
        return table.get(norm_key(m.group(1).split("_")))  # None if not an emoji
    return sanitize(stem) or None


def cmd_map(args):
    table = build_map(args.emoji_json)
    os.makedirs(args.out, exist_ok=True)
    used, mapped, unmapped = {}, 0, []
    for fname in sorted(os.listdir(args.src)):
        if not fname.lower().endswith(".png"):
            continue
        short = shortcode_for(fname[:-4], table)
        if not short:
            unmapped.append(fname)
            continue
        name, final, i = f"{args.prefix}{short}", f"{args.prefix}{short}", 2
        while final in used:
            final, i = f"{name}_{i}", i + 1
        used[final] = True
        shutil.copy(os.path.join(args.src, fname), os.path.join(args.out, f"{final}.png"))
        mapped += 1
    print(f"  mapped {mapped} files (prefix '{args.prefix}')", file=sys.stderr)
    if unmapped:
        print(f"  {len(unmapped)} skipped (no shortcode), e.g. {', '.join(unmapped[:4])}",
              file=sys.stderr)
    return 0


def _rasterize_one(svg2png, src, dest, size):
    try:
        svg2png(url=src, write_to=dest, output_width=size, output_height=size)
        return True
    except Exception as exc:  # malformed/empty SVGs shouldn't kill the batch
        print(f"  ! skip {os.path.basename(src)}: {exc}", file=sys.stderr)
        return False


def cmd_rasterize(args):
    try:
        from cairosvg import svg2png
    except ImportError:
        print("cairosvg not installed. Install it with:  python3 -m pip install --user cairosvg",
              file=sys.stderr)
        return 2
    os.makedirs(args.out, exist_ok=True)
    done = 0

    if args.fluent_assets:
        for entry in sorted(os.listdir(args.fluent_assets)):
            meta = os.path.join(args.fluent_assets, entry, "metadata.json")
            color = os.path.join(args.fluent_assets, entry, "Color")
            if not (os.path.isfile(meta) and os.path.isdir(color)):
                continue
            with open(meta, encoding="utf-8") as fh:
                uni = (json.load(fh).get("unicode") or "").strip()
            svgs = [f for f in os.listdir(color) if f.endswith(".svg")]
            if not uni or not svgs:
                continue
            cp = "_".join(uni.split())  # "1f1e6 1f1e8" -> codepoint filename form
            if _rasterize_one(svg2png, os.path.join(color, svgs[0]),
                              os.path.join(args.out, f"emoji_u{cp}.png"), args.size):
                done += 1
    else:  # flat --svg-dir: preserve the stem (emoji_u* or descriptive)
        for fname in sorted(os.listdir(args.svg_dir)):
            if not fname.lower().endswith(".svg"):
                continue
            if _rasterize_one(svg2png, os.path.join(args.svg_dir, fname),
                              os.path.join(args.out, fname[:-4] + ".png"), args.size):
                done += 1
            if done % 500 == 0 and done:
                print(f"  ...rasterized {done}", file=sys.stderr)
    print(f"  rasterized {done} svg -> png ({args.size}px)", file=sys.stderr)
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    m = sub.add_parser("map", help="map PNGs to shortcode-named PNGs")
    m.add_argument("--emoji-json", required=True)
    m.add_argument("--src", required=True)
    m.add_argument("--out", required=True)
    m.add_argument("--prefix", default="")
    m.set_defaults(func=cmd_map)

    r = sub.add_parser("rasterize", help="SVG -> 128px PNG via cairosvg")
    r.add_argument("--out", required=True)
    r.add_argument("--size", type=int, default=128)
    g = r.add_mutually_exclusive_group(required=True)
    g.add_argument("--svg-dir", help="flat dir of *.svg (stem preserved)")
    g.add_argument("--fluent-assets", help="Microsoft Fluent assets/ tree")
    r.set_defaults(func=cmd_rasterize)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
