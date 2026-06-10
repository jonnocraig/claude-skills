# Populating Your Slack with Open-Source Emojis & Animations

A practical guide for sourcing **openly-licensed** custom emojis/emotes/animations and
loading them into your Slack workspace for daily use. Researched and compiled May 2026.

> **TL;DR** — For a company workspace, pull from **Apache/MIT/CC0-licensed** packs
> (Noto Emoji, Microsoft Fluent UI, Blobmoji, Party Parrot core, Blobs). Avoid
> NonCommercial packs (Mutant Standard) and the now-proprietary JoyPixels. Resize to
> **128×128px, under 128KB**, then bulk-upload with the **Neutral Face Emoji Tools**
> browser extension. Full details below.

---

## 1. Where to get the emojis (open source, vetted for licensing)

### ✅ Safest for a company workspace (permissive, commercial-OK, minimal strings)

| Pack | What it is | Count | License | Link |
|------|-----------|-------|---------|------|
| **Noto Emoji (Google)** | Google's full emoji set, clean and modern. PNGs at 128px ready to go. | ~3,600 | **Apache-2.0** (images) | https://github.com/googlefonts/noto-emoji |
| **Microsoft Fluent UI Emoji** | Modern MS emoji, Color/Flat/Hi-Contrast styles. | ~1,500 | **MIT** | https://github.com/microsoft/fluentui-emoji |
| **Blobmoji** | The beloved legacy Android "blob" emoji, kept alive. 128px PNGs. | ~3,600 | **Apache-2.0** (images) | https://github.com/C1710/blobmoji |
| **Blobs.gg / BlobCats** | Extended blob reactions + blobcats (some animated). | Hundreds | **Apache-2.0** | https://blobs.gg · https://github.com/DuckOfDisorder/BlobCats |
| **Cult of the Party Parrot** (core) | The iconic animated party parrots — a Slack rite of passage. | 300+ | Core GIF: unlimited-use grant; CC-BY-SA 4.0 assets need attribution | https://cultofthepartyparrot.com · https://github.com/jmhobbs/cultofthepartyparrot.com |

### ✅ Fine with attribution (CC-BY / CC-BY-SA)

| Pack | Notes | License | Link |
|------|-------|---------|------|
| **Twemoji** (maintained fork) | Twitter's open emoji. Use the `jdecked` fork — original repo is archived. | Graphics **CC-BY 4.0**, code MIT | https://github.com/jdecked/twemoji |
| **OpenMoji** | 4,000+ emoji incl. many extras not in Unicode. | **CC-BY-SA 4.0** (attribution + ShareAlike) | https://openmoji.org · https://github.com/hfg-gmuend/openmoji |
| **Emojitwo** | The genuinely-free fork of *original* EmojiOne 2.2 (art is dated). | **CC-BY 4.0** | https://emojitwo.github.io |

### ⚠️ Convenient aggregators — vet before corporate use

| Pack | Caveat |
|------|--------|
| **Slackmojis** (https://slackmojis.com) | Huge, pre-sized for Slack, great animated section — **but** community-submitted and full of copyrighted memes/brands/sports logos. For a corporate Slack, cherry-pick the parrot/blob/generic categories and skip branded/celebrity content. |
| **wlonkly/slackmojis**, **seanprashad/slackmoji** (GitHub) | Pre-sized themed packs, but **no top-level license** and mixed sources (includes Pokémon/fan IP). Fine for community workspaces; for corporate, drop the fan-IP sets. |

### 🚫 Avoid (licensing risk)

| Pack | Why avoid |
|------|-----------|
| **JoyPixels** (formerly EmojiOne) | **No longer open source** — now freemium; free tier is *personal/educational only*. Business use requires a paid license. |
| **Mutant Standard / Mutant Remix** | High quality but **CC-BY-NC-SA 4.0** — the **NonCommercial** clause makes it legally risky for a for-profit workspace. OK only for personal/non-profit. |
| **Apple / Samsung / WhatsApp emoji** (found in some "emoji-data" repos) | **Proprietary & copyrighted.** Don't redistribute/upload. |

**My recommendation:** Build your daily-use set from **Noto Emoji + Fluent UI + Blobmoji**
(all permissive, no attribution burden) and add the **core Party Parrots + Blobs** for
fun animated reactions. That gives you thousands of clean, commercially-safe emoji with
zero licensing headaches.

---

## 2. Slack's technical requirements (confirmed from official docs)

| Constraint | Value |
|-----------|-------|
| **Formats** | JPG, PNG, or **GIF** (GIF is the only animated format) |
| **Max file size** | **Under 128 KB** (static *and* animated) — even 1 byte over is rejected |
| **Dimensions** | Square; **128 × 128 px** recommended for sharpest display |
| **Animated frames** | Up to **50 frames** per GIF |
| **Background** | Transparent (PNG) looks best |
| **Naming** | **Lowercase only**, no spaces; **underscores** are the safe separator |

> The 128 KB ceiling — not the frame cap — is the real bottleneck for animations.
> Most good animated emoji use ~5–15 frames, a reduced color palette, and simple looping motion.

---

## 3. Prep: resize & compress before uploading

Most open packs ship images larger than Slack allows. Batch-fix them first.

### Static PNGs (ImageMagick)

```bash
# Resize a whole folder to 128x128 and strip metadata
mogrify -resize 128x128 -strip *.png

# If any are still over 128KB, crush them with pngquant
pngquant --quality=65-90 --ext .png --force *.png
```

### Animated GIFs (gifsicle) — the hard part is staying under 128 KB

Apply these in order of impact until the file fits:

```bash
# 1. Resize first — usually the single biggest win
gifsicle -O3 --colors=256 --resize=128x128 in.gif -o out.gif

# 2. Add lossy compression if still too big (30 → 80 trades quality for size)
gifsicle -O3 --colors=128 --lossy=80 --resize=128x128 in.gif -o out.gif

# 3. Last resort: shrink dimensions and/or cut the palette harder
gifsicle -O3 --colors=64 --lossy=80 --resize=96x96 in.gif -o out.gif
```

**Levers:** `-O3` (max lossless optimization) · `--colors=N` (drop to 128/64/32) ·
`--lossy=N` · `--resize=` (128→96→64) · drop every Nth frame for long GIFs.

**No-install browser option:** [ezgif.com/resize](https://ezgif.com/resize) →
[ezgif.com/optimize](https://ezgif.com/optimize). Workflow: resize to 128×128 → remove
every 2nd frame → reduce colors to ~64 → optimize → confirm < 128 KB.

---

## 4. How to add them to Slack

### Option A — Manual (any plan, no tools, best for a handful)

1. In any message box, click the **smiley face icon** → **Add Emoji**.
   (Or go straight to `https://<yourworkspace>.slack.com/customize/emoji`.)
2. Click **Upload Image** and pick your file.
3. Enter a **name** (lowercase, underscores) → **Save**.

**Aliases** (a second shortcode for an existing emoji): workspace name →
**Customize** → **Add Alias** → **Choose Emoji** → type the alias → **Save**.

### Option B — Bulk upload (recommended for populating many at once)

Slack has **no official bulk-upload API** for standard workspaces, so bulk loading uses
community tools. Ranked by safety:

**🥇 Neutral Face Emoji Tools (browser extension) — lowest risk, recommended**
- Repo: https://github.com/takempf/neutral-face-emoji-tools (actively maintained, v4.x 2025)
- Listed on the Chrome Web Store as **"Slack Emoji Tools"**; Firefox as "Neutral Face Emoji Tools".
- How it works: on your `/customize/emoji` page it adds a **drag-and-drop bulk uploader**.
  **Each file's filename becomes the emoji name** — so name your files first
  (e.g. `party_parrot.gif`, `blob_wave.png`).
- Auth: uses your **existing logged-in browser session** — no tokens or passwords to paste. ✅

**🥈 CLI tools (for scripted / repeatable workflows — accept extra risk)**
- **emojipacks** (https://github.com/lambtron/emojipacks) — `npm i -g emojipacks`, driven by a
  YAML list of `name` + image `src`. Logs in with email/password/2FA (fragile with SSO).
- **emojme** (https://github.com/jackellenberger/emojme) — more powerful (upload/download/sync),
  but uses **undocumented endpoints** and requires extracting your `xoxc` token + `xoxd` cookie.
  ⚠️ Those are sensitive full-account credentials — see governance notes below.

**🥉 Enterprise Grid only — official API**
- **`admin.emoji.add`** (https://docs.slack.dev/reference/methods/admin.emoji.add/) — the only
  *supported* programmatic path. Needs an org-level app with `admin.teams:write`. Auditable and
  supported; use this instead of UI-scraping tools if you're on Grid.

---

## 5. Admin / governance checklist

- **Who can add:** By default any **member** (not guests) can add emoji. Owners/Admins can
  restrict via **Workspace settings → Roles & permissions → "Add and edit custom emoji"**.
- **Plan differences:** Custom emoji + aliases work on **all plans** (Free → Grid). Only the
  `admin.emoji.add` API is Grid-only.
- **Credential safety:** Avoid tools that ask you to paste `xoxc`/`xoxd` tokens or passwords
  into untrusted code — a leaked token impersonates your whole account. The session-based
  browser extension avoids this entirely.
- **Content governance:** Bulk upload amplifies the risk of offensive/NSFW or brand-impersonation
  emoji. Agree a naming convention, keep a removal process, and restrict bulk-add to trusted admins.
- **Attribution:** If you use CC-BY / CC-BY-SA packs (Twemoji, OpenMoji, some Party Parrot assets),
  drop a one-line credit somewhere (e.g. an internal wiki page) to satisfy the license.
- **Tool fragility:** Unofficial tools depend on Slack's UI/internal endpoints and can break after
  Slack changes (SSO especially breaks password-based tools). Don't build critical workflows on them.

---

## 6. Easiest route — one script

Two files in this folder do all the prep:
- **`prep-slack-emoji.sh`** — downloads packs and builds a ready-to-drag `slack-emoji-upload/` folder.
- **`emoji_namemap.py`** — maps codepoint filenames (`emoji_u1f600.png`) to real Slack
  shortcodes (`grinning.png`) using the MIT `iamcal/emoji-data` table (Slack's own naming lineage).

```bash
./prep-slack-emoji.sh                          # all packs (parrots + noto + blob + fluent)
PACKS="parrots noto" ./prep-slack-emoji.sh     # pick specific packs
ADD_DIR=~/my-gifs ./prep-slack-emoji.sh        # also fold in your own images
OUT_DIR=~/Desktop/emoji ./prep-slack-emoji.sh  # choose the output location
```

**Packs available:**

| Pack | Style | Count | Tools needed |
|------|-------|------:|--------------|
| `parrots` | Animated party parrots (GIF) | 86 | None |
| `noto` | Google Noto Emoji — full Unicode set | ~3,500 | None |
| `blob` | Google "blob" emoji | ~70 | None |
| `fluent` | Microsoft Fluent UI Emoji | ~3,100 | **SVG rasterizer** (`rsvg-convert`/`inkscape`) — auto-skips with an install hint if missing |

**Important — style prefixes:** general-purpose Unicode emoji *already exist natively in
Slack*, and Slack won't let a custom emoji override a built-in name. So `noto`/`blob`/`fluent`
get a prefix (`noto_`, `blob_`, `fluent_`) — you'll type `:noto_pizza:`, `:blob_thumbsup:`,
`:fluent_rocket:`. The parrots keep their original names (`:coffeeparrot:`). Override a prefix
with e.g. `NOTO_PREFIX= ` (empty = no prefix, but then most will clash with built-ins and be rejected).

The script also handles **skin-tone variants** (`noto_thumbsup_dark_skin`), de-dupes name
collisions, keeps everything ≤128KB, auto-compresses oversized GIFs with `gifsicle` if present,
and writes an `ATTRIBUTION.txt` (don't upload that one).

**Batching:** output is split into `batch-01/`, `batch-02/`, … folders of **500 emoji each**, so
you drag one folder's contents per upload round. Change the size with `BATCH_SIZE=250 ...`, or
disable with `BATCH_SIZE=0` for a single flat folder. (`ATTRIBUTION.txt` stays at the top level.)

Then install the **Slack Emoji Tools** browser extension, open `/customize/emoji`, and drag one
**`batch-NN/`** folder at a time onto the bulk uploader. Each filename becomes the emoji name.

### Full rollout plan (if hand-picking more packs)

1. **Pick your base set:** download Noto Emoji + Fluent UI + Blobmoji (all permissive).
2. **Add fun reactions:** grab the core Party Parrots and Blobs animated GIFs.
3. **Prep:** batch-resize to 128×128 and compress (§3); rename files to your desired shortcodes.
4. **Install** the Neutral Face Emoji Tools extension; open `/customize/emoji`.
5. **Drag-and-drop** a batch (do ~20–50 at a time so you can spot name collisions).
6. **Announce** the new emoji in a channel + post the attribution note for CC-BY packs.

---

### Sources
Slack official: [Add custom emoji & aliases](https://slack.com/help/articles/206870177) ·
[Manage emoji permissions](https://slack.com/help/articles/115005043766) ·
[admin.emoji.add](https://docs.slack.dev/reference/methods/admin.emoji.add/).
Packs & tools linked inline above.
