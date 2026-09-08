# lenslink.cam — the website

The marketing and documentation site: a static generator with **no
dependencies** (Python standard library only) and **no runtime**, published
free on Cloudflare Pages.

```
site/
  build.py          the generator — writes dist/
  check-links.py    verifies every internal link and #anchor resolves
  pages/            one HTML fragment per page, with front matter
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
- **The camera still behind it.** Drop a landscape image at
  `static/img/hero-feed.jpg` and `build.py` puts it behind that panel, the
  way the app draws its controls over live video; with no such file the
  panel keeps its tinted-glow background and the page requests nothing
  extra. Ideally a real frame from a LensLink camera. Aim for 1600px wide
  or more, and keep the interesting part of the picture out of the bottom
  third and the top-left corner — the control panel and the Live pill sit
  there. A scrim is applied automatically so white controls stay legible
  over any photo.

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

CI (`.github/workflows/build.yml`) builds the site and fails the pull
request on a broken internal link, but it cannot tell you that a sentence
became untrue.
