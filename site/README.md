# lenslink.cam — the website

The marketing and documentation site: a static generator with **no
dependencies** (Python standard library only) and **no runtime**, published
free on Cloudflare Pages.

```
site/
  build.py          the generator — writes dist/
  check-links.py    verifies every internal link and #anchor resolves
  pages/            one HTML fragment per page, with front matter (English)
  translations/     the same fragments in other languages, one folder each
  i18n/             the shell's strings: en.json, then one file per language
  static/           css, js, _headers, _redirects (copied verbatim)
  dist/             build output (git-ignored)
```

## Working on it

```bash
cd site
python3 build.py --serve      # builds dist/ and serves http://localhost:8000
python3 check-links.py        # run after a build; CI runs this too
```

`build.py` is deliberately boring: it wraps each fragment in the shared
shell (header, footer, docs sidebar), gives every `<h2>`/`<h3>` a slug id,
builds the "On this page" list from the `<h2>`s, and writes clean URLs
(`pages/docs/install.html` → `dist/docs/install/index.html`).

### Adding a page

1. Create `pages/<name>.html` (or `pages/docs/<name>.html`) starting with
   front matter, then `---`, then plain HTML:

   ```
   title: Screen mirroring
   description: One sentence for search results and link previews.
   ---
   <h1>Screen mirroring</h1>
   ...
   ```

2. A documentation page must also be listed in `DOC_ORDER` in `build.py` —
   that one list drives the sidebar, the previous/next footer links and
   the sitemap.

`{{REPO}}` and `{{TESTFLIGHT}}` in page bodies expand to the GitHub and
TestFlight URLs, so those live in one place.

A new doc page's sidebar label is a key, not a string: add it to
`i18n/en.json` (and every other language file) next to the others.

### Languages

English lives at the root and its URLs never change. Every other language
gets a prefix, and every page exists under every prefix:

| Prefix | `lang` | Name |
|---|---|---|
| `/de/` | `de` | Deutsch |
| `/es/` | `es` | Español |
| `/fr/` | `fr` | Français |
| `/ja/` | `ja` | 日本語 |
| `/pt-br/` | `pt-BR` | Português (Brasil) |
| `/zh-hans/` | `zh-Hans` | 简体中文 |

`LANGS` in `build.py` is that table. The site is translated in two layers.

**The shell** (navigation, sidebar, footer, "On this page", the notices
below, and the few strings the scripts write) comes from `i18n/<prefix>.json`.
`i18n/en.json` is the source: flat keys, plain text, `{name}` placeholders
that must survive translation. A missing file or key falls back to English
with a build warning. The scripts never carry English of their own: the
build writes the strings they need into each page as a
`<script type="application/json" id="i18n">` block, which the CSP allows
because it never runs.

**The pages** come from `translations/<prefix>/`, mirroring `pages/`:
`translations/de/docs/install.html` translates `pages/docs/install.html`.
Same front matter as the English page (keep `nav` and `script` exactly as
they are), plus a `source` line naming the English revision it was made
from:

```
title: LensLink installieren
description: ...
source: 3f2a9c81d0b4
---
<h1>LensLink installieren</h1>
...
```

`python3 build.py --source-hash pages/docs/install.html` prints that line;
with no path it lists every page's hash. Translate the words and leave the
structure alone:

- the same `<h2>`/`<h3>` headings, in the same order. The build gives them
  the English page's ids, so `/de/docs/install/#sideloading` works and a
  heading in Japanese still has an anchor;
- the same internal links (write them as `/docs/...`; the build adds the
  prefix), the same `{{REPO}}`-style placeholders, the same element ids and
  `data-*` attributes (the setup guide filters on them).

What a visitor gets:

- **A translation**: the page, in the language's shell, listed in the
  sitemap and in `hreflang` alternates on every version of the page.
- **A stale translation** (its `source` no longer matches the English
  file): the same, plus a small notice at the top linking to the English
  page, and a build warning. Update the text, then the `source` line. If
  the English edit added, removed or renamed headings or ids, the old
  translation's anchors can't be trusted, so the English page is shown
  instead until it is brought up to date.
- **No translation**: the English body in the translated shell, marked
  `lang="en"`, with a notice that it hasn't been translated yet, so links
  and navigation never dead-end. These pages point their canonical URL at
  the English page and stay out of the sitemap and the alternates, so
  search engines see one copy of the English text.

English pages carry a language switcher in the footer (and the header, on
wide screens). When a visitor's browser prefers a language that page has
a translation for, `site.js` offers it in a small banner in that language
(the `lang.suggest` string), which stays dismissed once closed.

Check a translation before opening a pull request:

```bash
python3 ../tools/l10n_site.py
```

It fails on anything that would break a page (missing or extra keys, a
lost placeholder, headings that don't line up, a link or id that went
missing). A stale translation is only ever a warning, structural
differences included, so editing an English page never fails CI; the
notice covers the gap until someone catches up.

To add a language: a row in `LANGS` (prefix, `lang` code, native name,
`og:locale`), an `i18n/<prefix>.json` with every key in `en.json`, and a
`translations/<prefix>/` folder as pages are done.

### Design

The site implements `docs/UI_DESIGN.md` — the same palette, the same
control metaphors, the same status vocabulary as the app and the plugin's
browser panel. Notably:

- Dark only, `#0E0F13` page, one accent (`#3D7BFF`), hairline borders.
- System font stack; monospaced tabular numerals for anything numeric.
- The wordmark is drawn in SVG from the same geometry as
  `assets/make-icon.py` (lens ring, aperture dot, link ring with its
  keyline gap) rather than a bitmap, so it stays crisp at any size.
- The home page's device panel is the app's Live screen rebuilt from those
  tokens — not a screenshot, so it can never drift out of date silently.
  If the app's control layout changes, update it here too.
- **The camera stills behind it.** Drop either or both of
  `static/img/hero-feed-landscape.*` and `static/img/hero-feed-portrait.*`
  into `static/img/` and `build.py` puts them behind that panel, the way
  the app draws its controls over live video. The stylesheet picks by
  viewport — portrait below 470px, where the panel drops 16:10 and stands
  tall, landscape above it — and either orientation stands in for a missing
  one. Only the one in use is downloaded. With neither file the panel keeps
  its tinted-glow background and the page requests nothing extra.

  Ideally real frames from a LensLink camera. Keep the subject out of the
  bottom third and the top-left corner, where the control panel and the
  Live pill sit; a scrim is applied automatically so white controls stay
  legible over any photo.

Copy follows the same rules as the app: American English, sentence case,
no exclamation marks, "Flashlight" not "Torch", "Green screen" not "chroma
key", and OBS's own names for OBS things.

## Deploying (Cloudflare Pages, free)

The site is live on Cloudflare Pages, connected to this repository. Pages
serves unlimited static requests on the free plan and the zone is already
in the account, so hosting costs nothing.

Build settings, if the project ever has to be recreated:

| Field | Value |
|---|---|
| Production branch | `main` |
| Framework preset | None |
| Build command | `python3 build.py` |
| Build output directory | `dist` |
| Root directory | `site` |

Custom domains (`lenslink.cam`, `www.lenslink.cam`) are added under the
project's **Custom domains** tab; the DNS records and certificate are
created automatically because the zone is in the same account.

Every push to `main` rebuilds and deploys; every pull request gets a
preview URL. The build image ships Python 3, and the generator imports
nothing outside the standard library, so there is no install step.

Note that Cloudflare's newer **Workers** import flow is a different
product: it asks for a deploy command as well, and needs a
`wrangler.jsonc` declaring `dist/` as an assets directory. This project
does not carry one — it is deployed as Pages.

### What is already configured in the repo

- `static/_headers` — security headers and cache lifetimes. The CSP allows
  `api.github.com`, which the download page calls to list the current
  release's files; nothing else is permitted.
- **Hashed asset names.** `build.py` renames `site.css`, `site.js` and
  `download.js` to include a content hash, and rewrites every reference.
  Cloudflare caches those files for hours at the edge and in the browser,
  so a fixed name meant a CSS fix could be deployed and still not reach
  anyone until the old copy expired. With the hash in the name, a deploy
  publishes new URLs and the stale ones are simply never requested again —
  which is also why `_headers` can cache them for a year as `immutable`.
  Note the zone's **Browser Cache TTL** setting overrides the `max-age` in
  `_headers` (it was rewriting 1 hour to 4); the hashed names make that
  setting irrelevant to correctness.
- `static/_redirects` — short links (`/github`, `/testflight`,
  `/download/latest`) and redirects for guessable paths.
- `robots.txt` and `sitemap.xml` are generated by `build.py`.

### Deploying by hand

If you would rather not connect the repository, run `python3 build.py` and
drag `site/dist` onto **Workers & Pages → Create → Pages → Upload
assets**. The result is identical.

## Things that stay in sync

The site restates what the app and the plugin do, so a change to either
can make a page wrong. The pages most likely to go stale:

| If you change | Update |
|---|---|
| A source property or its wording | `pages/docs/settings.html`, `pages/docs/connect.html` (status table) |
| A plugin-wide setting | `pages/docs/settings.html` |
| An app option or the Documentation screen | `pages/docs/settings.html` and the matching feature page |
| A `CONTROL` command or an `/api/` endpoint | `pages/docs/web-panel.html` |
| Release asset file names | `static/js/download.js` (the `ROWS` table) |
| The app's Live-screen layout | the device panel in `pages/index.html` |
| Any English page | nothing more: its translations go stale, which is expected. They show a notice until someone updates them and their `source` line |
| A shell string in `build.py`, or a string a script writes | `i18n/en.json`, and the same key in every other `i18n/*.json` |
| A heading, link, id or `data-*` attribute in an English page | the same change in each `translations/*/` copy when it is next updated (the checker insists once its `source` is current) |

CI (`.github/workflows/build.yml`) builds the site and fails the pull
request on a broken internal link, but it cannot tell you that a sentence
became untrue.
