#!/usr/bin/env python3
"""Static site generator for lenslink.cam.

Standard library only, no build dependencies: Cloudflare Pages runs
`python3 build.py` and publishes `dist/`.

Each file under `pages/` is an HTML fragment preceded by a small
`key: value` front-matter block terminated by a `---` line. The
generator wraps it in the shared shell (header, footer, and — for
anything under `pages/docs/` — the documentation sidebar), gives every
`<h2>` a slug id, builds the on-page contents list from those headings,
and emits clean URLs: `pages/download.html` -> `dist/download/index.html`.

Run from this directory:

    python3 build.py            # writes dist/
    python3 build.py --serve    # writes dist/ and serves it on :8000
"""

import glob
import hashlib
import html
import os
import re
import shutil
import sys
import unicodedata
from datetime import date

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(ROOT)
PAGES = os.path.join(ROOT, "pages")
STATIC = os.path.join(ROOT, "static")
DIST = os.path.join(ROOT, "dist")

SITE_URL = "https://lenslink.cam"
REPO_URL = "https://github.com/MyNamesEMurray/LensLink"
TESTFLIGHT_URL = "https://testflight.apple.com/join/N7Rth6m3"

# Stills from a real LensLink camera, shown behind the home page's control
# panel the way the app draws its controls over live video. Both are
# optional and either can stand in for the other; with neither, the panel
# keeps its tinted-glow background and the page asks the browser for nothing
# that isn't there. Any web image format works — match the stem, keep the
# extension.
#
# Two, because the panel already changes shape: below the breakpoint in
# site.css it drops 16:10 and stands tall, which is a portrait frame's
# aspect, and above it it is a wide screen, which is a landscape frame's.
FEED_STEMS = {"landscape": "img/hero-feed-landscape",
              "portrait": "img/hero-feed-portrait"}

# Documentation order. The sidebar, the previous/next footer links and
# the sitemap all read this one list, so a new page is added once.
DOC_ORDER = [
    ("Start here", [
        ("docs/index.html", "Overview"),
        ("docs/install.html", "Install"),
        ("docs/connect.html", "Connect OBS to your phone"),
    ]),
    ("Using LensLink", [
        ("docs/camera.html", "Camera, lenses and image"),
        ("docs/screen-mirroring.html", "Screen mirroring"),
        ("docs/audio.html", "Audio and lip sync"),
        ("docs/remote-start.html", "Remote start"),
        ("docs/web-panel.html", "Browser control panel"),
    ]),
    ("Reference", [
        ("docs/settings.html", "Settings reference"),
        ("docs/performance.html", "Latency and performance"),
        ("docs/troubleshooting.html", "Troubleshooting"),
        ("docs/faq.html", "FAQ"),
    ]),
]

DOC_PAGES = [p for _, group in DOC_ORDER for p in group]


def slug(text):
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = re.sub(r"[^a-zA-Z0-9]+", "-", text).strip("-").lower()
    return text or "section"


def read_page(path):
    """Split a page file into its front matter and its body."""
    with open(path, encoding="utf-8") as fh:
        raw = fh.read()
    meta, body = {}, raw
    if "\n---\n" in raw:
        head, body = raw.split("\n---\n", 1)
        for line in head.splitlines():
            if not line.strip():
                continue
            key, _, value = line.partition(":")
            meta[key.strip()] = value.strip()
    return meta, body.strip()


def url_for(page_path):
    """pages/docs/install.html -> /docs/install/ (index pages lose the name)."""
    rel = page_path.replace(os.sep, "/")
    rel = re.sub(r"\.html$", "", rel)
    if rel == "index":
        return "/"
    if rel.endswith("/index"):
        rel = rel[: -len("/index")]
    return "/%s/" % rel


def add_heading_ids(body):
    """Give every h2/h3 an id, and collect the h2s for the contents list."""
    toc = []

    def repl(match):
        level, attrs, text = match.group(1), match.group(2), match.group(3)
        existing = re.search(r'id="([^"]+)"', attrs)
        ident = existing.group(1) if existing else slug(text)
        if not existing:
            attrs = ' id="%s"%s' % (ident, attrs)
        if level == "2":
            toc.append((ident, re.sub(r"<[^>]+>", "", text)))
        anchor = '<a class="anchor" href="#%s" aria-label="Link to this section">#</a>' % ident
        return "<h%s%s>%s%s</h%s>" % (level, attrs, text, anchor, level)

    body = re.sub(r"<h([23])([^>]*)>(.*?)</h\1>", repl, body, flags=re.S)
    return body, toc


def nav_html(active):
    items = [("/", "home", "Home"),
             ("/download/", "download", "Download"),
             ("/docs/", "docs", "Documentation")]
    out = []
    for href, key, label in items:
        cls = ' class="on"' if key == active else ""
        out.append('<a href="%s"%s>%s</a>' % (href, cls, label))
    out.append('<a class="ext" href="%s">GitHub</a>' % REPO_URL)
    return "".join(out)


def sidebar_html(current):
    out = ['<nav class="side" aria-label="Documentation">']
    for group, pages in DOC_ORDER:
        out.append("<p class=\"side-head\">%s</p><ul>" % group)
        for path, label in pages:
            cls = ' class="on"' if path == current else ""
            out.append('<li><a href="%s"%s>%s</a></li>' % (url_for(path), cls, label))
        out.append("</ul>")
    out.append("</nav>")
    return "".join(out)


def prev_next_html(current):
    paths = [p for p, _ in DOC_PAGES]
    if current not in paths:
        return ""
    i = paths.index(current)
    out = ['<nav class="pager">']
    if i > 0:
        p, label = DOC_PAGES[i - 1]
        out.append('<a class="prev" href="%s"><span>Previous</span>%s</a>' % (url_for(p), label))
    if i < len(DOC_PAGES) - 1:
        p, label = DOC_PAGES[i + 1]
        out.append('<a class="next" href="%s"><span>Next</span>%s</a>' % (url_for(p), label))
    out.append("</nav>")
    return "".join(out)


# The app mark, drawn from the same geometry as assets/make-icon.py: lens
# ring, aperture dot, and the link ring separated by a keyline gap. The
# gradient and mask ids are suffixed per instance — a page carries the
# wordmark twice, and duplicate ids would be invalid HTML.
def mark_svg(suffix):
    return """<svg class="mark" viewBox="0 0 1024 1024" aria-hidden="true" focusable="false">
<defs><linearGradient id="ap-{s}" x1="0" y1="0" x2="0" y2="1">
<stop offset="0" stop-color="#6FA0FF"/><stop offset="1" stop-color="#2E5FD6"/></linearGradient>
<mask id="keyline-{s}"><rect width="1024" height="1024" fill="#fff"/>
<circle cx="718" cy="698" r="194" fill="#000"/></mask></defs>
<circle cx="468" cy="448" r="128" fill="url(#ap-{s})"/>
<path d="M468 130a318 318 0 1 0 0 636 318 318 0 1 0 0-636zm0 94a224 224 0 1 1 0 448 224 224 0 1 1 0-448z"
 fill="#3D7BFF" mask="url(#keyline-{s})"/>
<path d="M718 526a172 172 0 1 0 0 344 172 172 0 1 0 0-344zm0 66a106 106 0 1 1 0 212 106 106 0 1 1 0-212z"
 fill="#8FB4FF"/></svg>""".format(s=suffix)


def wordmark(suffix):
    return ('<a class="wordmark" href="/">%s<span>Lens<b>Link</b></span></a>'
            % mark_svg(suffix))

FOOTER_COLS = [
    ("Product", [("/download/", "Download"), ("/docs/install/", "Install guide"),
                 ("/docs/connect/", "Connect"), ("/docs/faq/", "FAQ")]),
    ("Documentation", [("/docs/camera/", "Camera and image"),
                       ("/docs/screen-mirroring/", "Screen mirroring"),
                       ("/docs/audio/", "Audio and lip sync"),
                       ("/docs/troubleshooting/", "Troubleshooting")]),
    ("Project", [(REPO_URL, "Source on GitHub"),
                 (REPO_URL + "/releases", "Release notes"),
                 (REPO_URL + "/issues", "Report a bug"),
                 (REPO_URL + "/blob/main/LICENSE", "License (GPL-2.0-or-later)")]),
]


def shell(meta, body, page_path, toc):
    is_doc = page_path.startswith("docs/")
    title = meta.get("title", "LensLink")
    full_title = title if title.startswith("LensLink") else "%s — LensLink" % title
    desc = meta.get("description", "")
    canonical = SITE_URL + url_for(page_path)
    active = meta.get("nav", "docs" if is_doc else "")

    head = [
        '<!doctype html>', '<html lang="en">', '<head>',
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
        '<title>%s</title>' % html.escape(full_title),
        '<meta name="description" content="%s">' % html.escape(desc),
        '<link rel="canonical" href="%s">' % canonical,
        '<meta property="og:title" content="%s">' % html.escape(full_title),
        '<meta property="og:description" content="%s">' % html.escape(desc),
        '<meta property="og:type" content="website">',
        '<meta property="og:url" content="%s">' % canonical,
        '<meta property="og:image" content="%s/img/social-preview.png">' % SITE_URL,
        '<meta name="twitter:card" content="summary_large_image">',
        '<link rel="icon" href="/img/icon.png" type="image/png">',
        '<link rel="apple-touch-icon" href="/img/icon.png">',
        '<link rel="stylesheet" href="/css/site.css">',
    ]
    if meta.get("script"):
        head.append('<script src="%s" defer></script>' % meta["script"])
    head += ['</head>', '<body%s>' % (' class="docs"' if is_doc else "")]

    header = [
        '<a class="skip" href="#main">Skip to content</a>',
        '<header class="top"><div class="wrap">',
        wordmark('top'),
        '<nav class="mainnav" aria-label="Main">%s</nav>' % nav_html(active),
        '<button class="menu" aria-expanded="false" aria-controls="sitenav">Menu</button>',
        '</div><nav id="sitenav" class="dropnav" aria-label="Main, small screens">%s</nav></header>'
        % nav_html(active),
    ]

    if is_doc:
        contents = ""
        if len(toc) > 2:
            links = "".join('<li><a href="#%s">%s</a></li>' % (i, html.escape(t)) for i, t in toc)
            contents = '<aside class="toc"><p>On this page</p><ul>%s</ul></aside>' % links
        main = ['<div class="doclayout wrap">', sidebar_html(page_path),
                '<main id="main" class="doc">', body, prev_next_html(page_path),
                '</main>', contents, '</div>']
    else:
        main = ['<main id="main">', body, '</main>']

    cols = []
    for name, links in FOOTER_COLS:
        items = "".join('<li><a href="%s">%s</a></li>' % (h, l) for h, l in links)
        cols.append('<div><p>%s</p><ul>%s</ul></div>' % (name, items))
    footer = [
        '<footer class="foot"><div class="wrap">',
        '<div class="foot-brand">%s<p>Use an iPhone or iPad as a camera in OBS Studio, '
        'over Wi-Fi or USB. Free and open source.</p></div>' % wordmark('foot'),
        '<div class="foot-cols">%s</div>' % "".join(cols),
        '</div><div class="wrap foot-legal"><p>&copy; %d LensLink contributors. '
        'Not affiliated with Apple or the OBS Project.</p>'
        '<p>Built as a static site on Cloudflare Pages.</p></div></footer>' % date.today().year,
        '<script src="/js/site.js" defer></script>',
        '</body></html>',
    ]
    return "\n".join(head + header + main + footer)


# Stylesheets and scripts are copied out under a content-hashed name, and
# every reference to them is rewritten to match. Cloudflare caches these for
# hours at the edge and in the browser, so a fixed name means a CSS change
# can be deployed and still not reach anyone until the old copy expires. A
# hashed name changes with the content, so a deploy is picked up immediately
# and the old URL is never requested again.
FINGERPRINT = ["css/site.css", "js/site.js", "js/download.js"]


def fingerprint_assets():
    """Rename the built assets to <name>.<hash>.<ext>; return {old: new}."""
    mapping = {}
    for rel in FINGERPRINT:
        path = os.path.join(DIST, rel)
        if not os.path.exists(path):
            continue
        with open(path, "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()[:10]
        stem, ext = os.path.splitext(rel)
        hashed = "%s.%s%s" % (stem, digest, ext)
        os.rename(path, os.path.join(DIST, hashed))
        mapping["/" + rel] = "/" + hashed
    return mapping


def collect_pages():
    found = []
    for dirpath, _, filenames in os.walk(PAGES):
        for name in sorted(filenames):
            if name.endswith(".html"):
                rel = os.path.relpath(os.path.join(dirpath, name), PAGES)
                found.append(rel.replace(os.sep, "/"))
    return sorted(found)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def build():
    if os.path.isdir(DIST):
        shutil.rmtree(DIST)
    os.makedirs(DIST)

    shutil.copytree(STATIC, DIST, dirs_exist_ok=True)

    # Images shared with the repository, so the site never keeps a second
    # copy of the artwork that assets/make-icon.py generates.
    img = os.path.join(DIST, "img")
    os.makedirs(img, exist_ok=True)
    for src, dst in [("assets/logo.png", "icon.png"),
                     ("assets/social-preview.png", "social-preview.png"),
                     ("assets/screen-fit-transform.png", "screen-fit-transform.png")]:
        shutil.copyfile(os.path.join(REPO, src), os.path.join(img, dst))

    assets = fingerprint_assets()

    # The optional camera stills behind the hero panel: whichever of the two
    # orientations exist, declared as custom properties the stylesheet picks
    # between by viewport.
    props = []
    for name, stem in sorted(FEED_STEMS.items()):
        found = glob.glob(os.path.join(DIST, stem + ".*"))
        if found:
            rel = os.path.relpath(found[0], DIST).replace(os.sep, "/")
            props.append("--feed-%s:url('/%s')" % (name, rel))
    feed_class = " has-feed" if props else ""
    feed_style = (' style="%s"' % ";".join(props)) if props else ""

    urls = []
    for rel in collect_pages():
        meta, body = read_page(os.path.join(PAGES, rel))
        body, toc = add_heading_ids(body)
        body = (body.replace("{{TESTFLIGHT}}", TESTFLIGHT_URL)
                    .replace("{{REPO}}", REPO_URL)
                    .replace("{{FEED}}", feed_class)
                    .replace("{{FEED_STYLE}}", feed_style))
        out = shell(meta, body, rel, toc)
        for old, new in assets.items():
            out = out.replace(old, new)
        target = url_for(rel)
        if rel == "404.html":
            write(os.path.join(DIST, "404.html"), out)
            continue
        write(os.path.join(DIST, target.strip("/"), "index.html")
              if target != "/" else os.path.join(DIST, "index.html"), out)
        urls.append(target)

    today = date.today().isoformat()
    entries = "".join(
        "<url><loc>%s%s</loc><lastmod>%s</lastmod></url>" % (SITE_URL, u, today)
        for u in sorted(urls))
    write(os.path.join(DIST, "sitemap.xml"),
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">%s</urlset>' % entries)
    write(os.path.join(DIST, "robots.txt"),
          "User-agent: *\nAllow: /\n\nSitemap: %s/sitemap.xml\n" % SITE_URL)

    print("built %d pages into %s" % (len(urls) + 1, DIST))


if __name__ == "__main__":
    build()
    if "--serve" in sys.argv:
        import http.server
        import functools
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=DIST)
        print("serving http://localhost:8000")
        http.server.HTTPServer(("", 8000), handler).serve_forever()
