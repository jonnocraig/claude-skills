#!/usr/bin/env python3
"""emoji_namemap.py — map codepoint-named emoji PNGs to Slack shortcodes.

Many open-source emoji packs name files by Unicode codepoint
(e.g. ``emoji_u1f600.png``), which makes useless Slack shortcodes. This tool
turns them into human shortcodes (``grinning.png``) using the MIT-licensed
``iamcal/emoji-data`` name table — the same naming lineage Slack uses, so the
results feel native.

Pure standard library. Two subcommands:

  map       Copy <src>/emoji_u*.png  ->  <out>/<prefix><shortcode>.png
  manifest  For Microsoft Fluent assets: print "<codepoints>\\t<svgpath>" lines
            so a rasterizer can turn them into codepoint PNGs for `map`.

Example:
  emoji_namemap.py map --emoji-json emoji.json --src noto/png/128 \\
      --out out --prefix noto_
"""
import argparse
import json
import os
import re
import shutil
import sys

# Trailing skin-tone modifiers -> readable suffix (Slack uses skin-tone-2..6).
SKIN_TONES = {
    "1F3FB": "light_skin",
    "1F3FC": "medium_light_skin",
    "1F3FD": "medium_skin",
    "1F3FE": "medium_dark_skin",
    "1F3FF": "dark_skin",
}
# Variation selector / ZWJ noise we strip before matching codepoint sequences.
IGNORE_CP = {"FE0F"}


def norm_key(codepoints):
    """Uppercase, drop FE0F, join with '-' -> canonical match key."""
    return "-".join(cp.upper() for cp in codepoints if cp.upper() not in IGNORE_CP)


def sanitize(name):
    """Force a string into a valid Slack shortcode: [a-z0-9_]."""
    name = re.sub(r"[^a-z0-9]+", "_", name.lower())
    return re.sub(r"_+", "_", name).strip("_")


def best_short(rec):
    """Pick the friendliest shortcode for a record.

    emoji-data's primary ``short_name`` is sometimes punctuation-y (``+1`` ->
    ``1``). Prefer an alias that's word-like (starts with a letter), falling
    back to the primary name.
    """
    candidates = rec.get("short_names") or []
    primary = rec.get("short_name")
    if primary and primary not in candidates:
        candidates = [primary] + candidates
    cleaned = [(c, sanitize(c)) for c in candidates]
    cleaned = [(orig, s) for orig, s in cleaned if s]
    if not cleaned:
        return None
    # Prefer names whose sanitized form begins with a letter.
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
        key = norm_key(unified.split("-"))
        # First writer wins, but prefer the shortest/base sequence for a key.
        table.setdefault(key, sanitize(short))

    for rec in data:
        short = best_short(rec)
        add(rec.get("unified"), short)
        add(rec.get("non_qualified"), short)
        # Skin-tone variants: parent short_name + readable tone suffix.
        for variant in (rec.get("skin_variations") or {}).values():
            for field in ("unified", "non_qualified"):
                uni = variant.get(field)
                if not uni:
                    continue
                cps = [c for c in uni.split("-") if c.upper() not in IGNORE_CP]
                tones = [SKIN_TONES[c.upper()] for c in cps if c.upper() in SKIN_TONES]
                suffix = "_".join(tones) if tones else "tone"
                add(uni, f"{short}_{suffix}")
    return table


FNAME_RE = re.compile(r"^emoji_u([0-9a-fA-F_]+)\.png$")


def codepoints_from_filename(fname):
    m = FNAME_RE.match(fname)
    if not m:
        return None
    return m.group(1).split("_")


def cmd_map(args):
    table = build_map(args.emoji_json)
    os.makedirs(args.out, exist_ok=True)

    used, mapped, unmapped = {}, 0, []
    for fname in sorted(os.listdir(args.src)):
        cps = codepoints_from_filename(fname)
        if cps is None:
            continue
        short = table.get(norm_key(cps))
        if not short:
            unmapped.append(fname)
            continue
        name = f"{args.prefix}{short}"
        # De-dupe shortcode collisions deterministically.
        final, i = name, 2
        while final in used:
            final, i = f"{name}_{i}", i + 1
        used[final] = True
        shutil.copy(os.path.join(args.src, fname),
                    os.path.join(args.out, f"{final}.png"))
        mapped += 1

    print(f"  mapped {mapped} files (prefix '{args.prefix}')", file=sys.stderr)
    if unmapped:
        print(f"  {len(unmapped)} unmapped (no shortcode in table), e.g. "
              f"{', '.join(unmapped[:5])}", file=sys.stderr)
    return 0


def cmd_manifest(args):
    """Emit '<codepoints>\\t<svg path>' for each Fluent emoji (Color style)."""
    count = 0
    for entry in sorted(os.listdir(args.assets)):
        meta = os.path.join(args.assets, entry, "metadata.json")
        if not os.path.isfile(meta):
            continue
        with open(meta, encoding="utf-8") as fh:
            uni = (json.load(fh).get("unicode") or "").strip()
        if not uni:
            continue
        # Fluent style folder: <entry>/Color/<slug>_color.svg
        color = os.path.join(args.assets, entry, "Color")
        if not os.path.isdir(color):
            continue
        svgs = [f for f in os.listdir(color) if f.endswith(".svg")]
        if not svgs:
            continue
        # Fluent unicode looks like "1f600" or "1f1e6 1f1e8" (space-separated).
        cps = "_".join(uni.split())
        print(f"{cps}\t{os.path.join(color, svgs[0])}")
        count += 1
    print(f"  manifest: {count} fluent emoji", file=sys.stderr)
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    m = sub.add_parser("map", help="map codepoint PNGs to shortcode PNGs")
    m.add_argument("--emoji-json", required=True)
    m.add_argument("--src", required=True)
    m.add_argument("--out", required=True)
    m.add_argument("--prefix", default="")
    m.set_defaults(func=cmd_map)

    man = sub.add_parser("manifest", help="emit Fluent codepoint->svg manifest")
    man.add_argument("--assets", required=True)
    man.set_defaults(func=cmd_manifest)

    args = p.parse_args()
    return args.func(args)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except BrokenPipeError:
        # Downstream closed the pipe (e.g. `| head`) — exit quietly.
        sys.exit(0)
