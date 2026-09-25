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
import json
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
I18N = os.path.join(ROOT, "i18n")
TRANSLATIONS = os.path.join(ROOT, "translations")

SITE_URL = "https://lenslink.cam"
REPO_URL = "https://github.com/MyNamesEMurray/LensLink"
TESTFLIGHT_URL = "https://testflight.apple.com/join/N7Rth6m3"
APPSTORE_URL = "https://apps.apple.com/app/lenslink-camera/id6790673163"
APPSTORE_ID = "6790673163"

LANGS = [
    ("", "en", "English", "en_US"),
    ("de", "de", "Deutsch", "de_DE"),
    ("es", "es", "Español", "es_ES"),
    ("fr", "fr", "Français", "fr_FR"),
    ("ja", "ja", "日本語", "ja_JP"),
    ("pt-br", "pt-BR", "Português (Brasil)", "pt_BR"),
    ("zh-hans", "zh-Hans", "简体中文", "zh_CN"),
]

JS_STRINGS = {
    None: ("docs.all_pages",),
    "/js/download.js": ("download.", "os."),
    "/js/setup.js": ("setup.",),
}

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
    ("docs.group.start", [
        ("docs/index.html", "docs.page.index"),
        ("docs/install.html", "docs.page.install"),
        ("docs/connect.html", "docs.page.connect"),
    ]),
    ("docs.group.using", [
        ("docs/camera.html", "docs.page.camera"),
        ("docs/screen-mirroring.html", "docs.page.screen_mirroring"),
        ("docs/audio.html", "docs.page.audio"),
        ("docs/remote-start.html", "docs.page.remote_start"),
        ("docs/web-panel.html", "docs.page.web_panel"),
    ]),
    ("docs.group.reference", [
        ("docs/settings.html", "docs.page.settings"),
        ("docs/performance.html", "docs.page.performance"),
        ("docs/troubleshooting.html", "docs.page.troubleshooting"),
        ("docs/faq.html", "docs.page.faq"),
    ]),
]

DOC_PAGES = [p for _, group in DOC_ORDER for p in group]

def warn(message):
    print("warning: %s" % message, file=sys.stderr)


def flatten(data, prefix=""):
    out = {}
    for key, value in data.items():
        if isinstance(value, dict):
            out.update(flatten(value, prefix + key + "."))
        else:
            out[prefix + key] = value
    return out


def load_strings(name):
    path = os.path.join(I18N, name + ".json")
    if not os.path.exists(path):
        return None
    with open(path, encoding="utf-8") as fh:
        return flatten(json.load(fh))


class Locale:
    def __init__(self, prefix, code, name, og, strings, english):
        self.prefix, self.code, self.name, self.og = prefix, code, name, og
        self.strings, self.english = strings, english

    def own(self, key):
        value = self.strings.get(key)
        return value if isinstance(value, str) and value else None

    def t(self, key, **values):
        text = self.own(key) or self.english[key]
        for name, value in values.items():
            text = text.replace("{%s}" % name, str(value))
        return text

    def h(self, key, **values):
        return html.escape(self.t(key, **values), quote=False)

    def a(self, key, **values):
        return html.escape(self.t(key, **values))

    def url(self, url):
        return "/%s%s" % (self.prefix, url) if self.prefix else url

    def js(self, prefixes):
        return {k: self.t(k) for k in self.english
                if any(k.startswith(p) for p in prefixes)}


def load_locales():
    english = load_strings("en")
    locales = []
    for prefix, code, name, og in LANGS:
        strings = english
        if prefix:
            try:
                strings = load_strings(prefix)
            except ValueError as err:
                warn("i18n/%s.json is not valid JSON (%s); its shell is in English" % (prefix, err))
                strings = {}
            if strings is None:
                warn("i18n/%s.json not found; its shell is in English" % prefix)
                strings = {}
            else:
                missing = [k for k in english
                           if not (isinstance(strings.get(k), str) and strings.get(k))]
                if missing:
                    warn("i18n/%s.json lacks %d key(s), shown in English: %s"
                         % (prefix, len(missing), ", ".join(missing)))
        locales.append(Locale(prefix, code, name, og, strings, english))
    return locales


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


def source_hash(page_path):
    with open(page_path, "rb") as fh:
        data = fh.read().replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()[:12]


def url_for(page_path):
    """pages/docs/install.html -> /docs/install/ (index pages lose the name)."""
    rel = page_path.replace(os.sep, "/")
    rel = re.sub(r"\.html$", "", rel)
    if rel == "index":
        return "/"
    if rel.endswith("/index"):
        rel = rel[: -len("/index")]
    return "/%s/" % rel


HEADING = re.compile(r"<h([23])([^>]*)>(.*?)</h\1>", re.S)


def heading_ids(body):
    out = []
    for match in HEADING.finditer(body):
        existing = re.search(r'id="([^"]+)"', match.group(2))
        out.append((match.group(1), existing.group(1) if existing else slug(match.group(3))))
    return out


def add_heading_ids(body, anchors=True, label="Link to this section", ids=None):
    """Give every h2/h3 an id, and collect the h2s for the contents list.

    `anchors` adds the hover-revealed # link beside each heading. That earns
    its place in the documentation, where headings are destinations people
    link each other to; on the marketing pages the headings are copy, and a
    stray # on hover is just noise."""
    toc = []
    count = [0]

    def repl(match):
        level, attrs, text = match.group(1), match.group(2), match.group(3)
        index = count[0]
        count[0] += 1
        existing = re.search(r'id="([^"]+)"', attrs)
        if existing:
            ident = existing.group(1)
        elif ids is not None:
            ident = ids[index]
        else:
            ident = slug(text)
        if not existing:
            attrs = ' id="%s"%s' % (ident, attrs)
        if level == "2":
            toc.append((ident, re.sub(r"<[^>]+>", "", text)))
        anchor = ('<a class="anchor" href="#%s" aria-label="%s">#</a>'
                  % (ident, html.escape(label))) if anchors else ""
        return "<h%s%s>%s%s</h%s>" % (level, attrs, text, anchor, level)

    body = HEADING.sub(repl, body)
    return body, toc


HREF = re.compile(r'href="(/[^"]*)"')
ELEMENT_ID = re.compile(r'(?<![\w-])id="([^"]*)"')


def localize_links(body, loc, known):
    def repl(match):
        href = match.group(1)
        path = re.split(r"[?#]", href, 1)[0]
        return 'href="%s"' % loc.url(href) if path in known else match.group(0)
    return HREF.sub(repl, body)


def nav_html(active, loc):
    items = [("/", "home", "nav.home"),
             ("/download/", "download", "nav.download"),
             ("/setup/", "setup", "nav.setup"),
             ("/docs/", "docs", "nav.docs")]
    out = []
    for href, key, label in items:
        cls = ' class="on"' if key == active else ""
        out.append('<a href="%s"%s>%s</a>' % (loc.url(href), cls, loc.h(label)))
    out.append('<a class="ext" href="%s">GitHub</a>' % REPO_URL)
    return "".join(out)


def sidebar_html(current, loc):
    out = ['<nav class="side" aria-label="%s">' % loc.a("docs.label")]
    for group, pages in DOC_ORDER:
        out.append("<p class=\"side-head\">%s</p><ul>" % loc.h(group))
        for path, label in pages:
            cls = ' class="on"' if path == current else ""
            out.append('<li><a href="%s"%s>%s</a></li>'
                       % (loc.url(url_for(path)), cls, loc.h(label)))
        out.append("</ul>")
    out.append("</nav>")
    return "".join(out)


def prev_next_html(current, loc, lang_attr=""):
    paths = [p for p, _ in DOC_PAGES]
    if current not in paths:
        return ""
    i = paths.index(current)
    out = ['<nav class="pager"%s>' % lang_attr]
    if i > 0:
        p, label = DOC_PAGES[i - 1]
        out.append('<a class="prev" href="%s"><span>%s</span>%s</a>'
                   % (loc.url(url_for(p)), loc.h("docs.previous"), loc.h(label)))
    if i < len(DOC_PAGES) - 1:
        p, label = DOC_PAGES[i + 1]
        out.append('<a class="next" href="%s"><span>%s</span>%s</a>'
                   % (loc.url(url_for(p)), loc.h("docs.next"), loc.h(label)))
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


def wordmark(suffix, loc):
    return ('<a class="wordmark" href="%s">%s<span>Lens<b>Link</b></span></a>'
            % (loc.url("/"), mark_svg(suffix)))


GLOBE = ('<svg class="globe" viewBox="0 0 24 24" fill="none" stroke="currentColor" '
         'stroke-width="1.8" stroke-linecap="round" aria-hidden="true" focusable="false">'
         '<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/>'
         '<path d="M12 3a14 14 0 0 1 0 18a14 14 0 0 1 0-18z"/></svg>')

FOOTER_COLS = [
    ("footer.product", [("/download/", "footer.download"), ("/setup/", "footer.setup"),
                        ("/docs/connect/", "footer.connect"), ("/docs/faq/", "footer.faq")]),
    ("footer.docs", [("/docs/camera/", "footer.camera"),
                     ("/docs/screen-mirroring/", "footer.screen_mirroring"),
                     ("/docs/audio/", "footer.audio"),
                     ("/docs/troubleshooting/", "footer.troubleshooting")]),
    ("footer.project", [(REPO_URL, "footer.source"),
                        (REPO_URL + "/releases", "footer.releases"),
                        (REPO_URL + "/issues", "footer.bug"),
                        (REPO_URL + "/blob/main/LICENSE", "footer.license"),
                        ("/support/", "footer.support"), ("/privacy/", "footer.privacy")]),
]


def lang_items(page):
    loc = page["loc"]
    out = []
    for other in page["locales"]:
        href = other.url("/" if page["rel"] == "404.html" else page["url"])
        attrs = ' hreflang="%s" lang="%s"' % (other.code, other.code)
        if other is loc:
            attrs += ' aria-current="page"'
        suggest = other.own("lang.suggest")
        if (not loc.prefix and other.prefix and suggest
                and other in page["versions"]):
            attrs += ' data-suggest="%s" data-dismiss="%s"' % (
                html.escape(suggest), other.a("lang.dismiss"))
        out.append('<li><a href="%s"%s>%s</a></li>' % (href, attrs, html.escape(other.name)))
    return "".join(out)


def lang_picker(page):
    loc = page["loc"]
    return ('<details class="langpick"><summary>%s<span class="vh">%s</span>'
            '<span class="code">%s</span></summary><ul>%s</ul></details>'
            % (GLOBE, loc.h("lang.label"), loc.code.split("-")[0].upper(), lang_items(page)))


def lang_nav(page):
    return ('<nav class="langs" aria-label="%s">%s<ul>%s</ul></nav>'
            % (page["loc"].a("lang.label"), GLOBE, lang_items(page)))


def notice_html(page):
    loc, mode = page["loc"], page["mode"]
    if mode == "stale":
        return ('<p class="l10n-note" role="note">%s <a href="%s" hreflang="en">%s</a></p>'
                % (loc.h("l10n.stale"), page["url"], loc.h("l10n.stale_link")))
    if mode == "fallback":
        return ('<p class="l10n-note" role="note" lang="%s">%s</p>'
                % (loc.code, loc.h("l10n.untranslated")))
    return ""


def js_strings(page):
    loc = page["loc"]
    strings = loc.js(JS_STRINGS[None])
    script = page["meta"].get("script")
    if script in JS_STRINGS:
        body_loc = page["english"] if page["mode"] == "fallback" else loc
        strings.update(body_loc.js(JS_STRINGS[script]))
    data = json.dumps(strings, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return '<script type="application/json" id="i18n">%s</script>' % data.replace("<", "\\u003c")


def shell(page):
    meta, body, page_path, toc = page["meta"], page["body"], page["rel"], page["toc"]
    loc, mode = page["loc"], page["mode"]
    fallback = mode == "fallback"
    is_doc = page_path.startswith("docs/")
    title = meta.get("title", "LensLink")
    full_title = title if title.startswith("LensLink") else loc.t("title", title=title)
    desc = meta.get("description", "")
    canonical = SITE_URL + (page["url"] if fallback else loc.url(page["url"]))
    active = meta.get("nav", "docs" if is_doc else "")

    alternates = []
    if len(page["versions"]) > 1:
        alternates = ['<link rel="alternate" hreflang="%s" href="%s%s">'
                      % (v.code, SITE_URL, v.url(page["url"])) for v in page["versions"]]
        alternates.append('<link rel="alternate" hreflang="x-default" href="%s%s">'
                          % (SITE_URL, page["url"]))

    head = [
        '<!doctype html>', '<html lang="%s">' % loc.code, '<head>',
        '<meta charset="utf-8">',
        '<meta name="viewport" content="width=device-width,initial-scale=1">',
        '<title>%s</title>' % html.escape(full_title),
        '<meta name="description" content="%s">' % html.escape(desc),
        '<link rel="canonical" href="%s">' % canonical,
    ] + alternates + [
        '<meta property="og:title" content="%s">' % html.escape(full_title),
        '<meta property="og:description" content="%s">' % html.escape(desc),
        '<meta property="og:type" content="website">',
        '<meta property="og:locale" content="%s">' % loc.og,
        '<meta property="og:url" content="%s">' % canonical,
        '<meta property="og:image" content="%s/img/social-preview.png">' % SITE_URL,
        '<meta name="twitter:card" content="summary_large_image">',
        '<link rel="icon" href="/img/icon.png" type="image/png">',
        '<link rel="apple-touch-icon" href="/img/icon.png">',
        '<meta name="apple-itunes-app" content="app-id=%s">' % APPSTORE_ID,
        '<link rel="stylesheet" href="/css/site.css">',
    ]
    if meta.get("script"):
        head.append('<script src="%s" defer></script>' % meta["script"])
    head += ['</head>', '<body%s>' % (' class="docs"' if is_doc else "")]

    header = [
        '<a class="skip" href="#main">%s</a>' % loc.h("skip"),
        '<header class="top"><div class="wrap">',
        wordmark('top', loc),
        '<nav class="mainnav" aria-label="%s">%s</nav>' % (loc.a("nav.label"), nav_html(active, loc)),
        lang_picker(page),
        '<button class="menu" aria-expanded="false" aria-controls="sitenav">%s</button>'
        % loc.h("menu"),
        '</div><nav id="sitenav" class="dropnav" aria-label="%s">%s</nav></header>'
        % (loc.a("nav.label_small"), nav_html(active, loc)),
    ]

    note = notice_html(page)
    body_lang = ' lang="en"' if fallback else ""
    shell_lang = ' lang="%s"' % loc.code if fallback else ""
    if is_doc:
        contents = ""
        if len(toc) > 2:
            links = "".join('<li><a href="#%s">%s</a></li>' % (i, html.escape(t)) for i, t in toc)
            contents = ('<aside class="toc"><p>%s</p><ul%s>%s</ul></aside>'
                        % (loc.h("docs.on_this_page"), body_lang, links))
        main = ['<div class="doclayout wrap">', sidebar_html(page_path, loc),
                '<main id="main" class="doc"%s>' % body_lang, note, body,
                prev_next_html(page_path, loc, shell_lang),
                '</main>', contents, '</div>']
    else:
        main = ['<main id="main"%s>' % body_lang,
                '<div class="wrap">%s</div>' % note if note else "", body, '</main>']
    main = [part for part in main if part]

    cols = []
    for name, links in FOOTER_COLS:
        items = "".join('<li><a href="%s">%s</a></li>'
                        % (loc.url(h) if h.startswith("/") else h, loc.h(l)) for h, l in links)
        cols.append('<div><p>%s</p><ul>%s</ul></div>' % (loc.h(name), items))
    footer = [
        '<footer class="foot"><div class="wrap">',
        '<div class="foot-brand">%s<p>%s</p></div>' % (wordmark('foot', loc), loc.h("footer.blurb")),
        '<div class="foot-cols">%s</div>' % "".join(cols),
        '</div><div class="wrap foot-legal">%s<p>%s</p><p>%s</p></div></footer>'
        % (lang_nav(page), loc.h("footer.copyright", year=date.today().year), loc.h("footer.built")),
        js_strings(page),
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
FINGERPRINT = ["css/site.css", "js/site.js", "js/download.js", "js/setup.js"]


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


def collect_translations(locales, pages):
    found = {}
    if not os.path.isdir(TRANSLATIONS):
        return found
    prefixes = {loc.prefix for loc in locales if loc.prefix}
    for dirpath, _, filenames in os.walk(TRANSLATIONS):
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, TRANSLATIONS).replace(os.sep, "/")
            prefix, _, page = rel.partition("/")
            if prefix not in prefixes:
                warn("translations/%s: unknown language, ignored" % rel)
            elif page not in pages:
                warn("translations/%s: no pages/%s to translate, ignored" % (rel, page))
            else:
                found[(prefix, page)] = full
    return found


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


CJK_BREAK = re.compile(r"(?<=[\u3000-\u9fff\uff00-\uffef])\n[ \t]*(?=[\u3000-\u9fff\uff00-\uffef])")


def join_cjk_lines(body):
    parts = re.split(r"(<pre[\s>].*?</pre>)", body, flags=re.S)
    return "".join(p if p.startswith("<pre") else CJK_BREAK.sub("", p) for p in parts)


def render_body(body, feed_class, feed_style):
    return (body.replace("{{TESTFLIGHT}}", TESTFLIGHT_URL)
                .replace("{{APPSTORE}}", APPSTORE_URL)
                .replace("{{REPO}}", REPO_URL)
                .replace("{{FEED}}", feed_class)
                .replace("{{FEED_STYLE}}", feed_style))


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

    locales = load_locales()
    english = locales[0]
    pages = collect_pages()
    translations = collect_translations(locales, pages)
    known = {url_for(rel) for rel in pages if rel != "404.html"}
    sources = {rel: read_page(os.path.join(PAGES, rel)) for rel in pages}

    resolved = {}
    counts = {loc.prefix: [0, 0] for loc in locales if loc.prefix}
    for (prefix, rel), path in sorted(translations.items()):
        en_meta, en_body = sources[rel]
        en_ids = heading_ids(en_body)
        tr_meta, body = read_page(path)
        meta = dict(en_meta)
        meta.update({k: v for k, v in tr_meta.items() if k != "source"})
        label = "translations/%s/%s" % (prefix, rel)
        stale = tr_meta.get("source") != source_hash(os.path.join(PAGES, rel))
        matches = ([m.group(1) for m in HEADING.finditer(body)] == [lv for lv, _ in en_ids]
                   and set(ELEMENT_ID.findall(body)) == set(ELEMENT_ID.findall(en_body)))
        if stale and not matches:
            warn("%s is stale and its headings or ids no longer match pages/%s; "
                 "showing the English page until it is updated" % (label, rel))
            continue
        if stale:
            warn("%s is stale: pages/%s changed since source %s"
                 % (label, rel, tr_meta.get("source") or "(missing)"))
        ids = [ident for _, ident in en_ids] if matches else None
        if not matches:
            warn("%s: its h2/h3 headings or ids do not match pages/%s, "
                 "so its anchors fall back to slugs" % (label, rel))
        resolved[(prefix, rel)] = ("stale" if stale else "translated", meta, body, ids)
        counts[prefix][0] += 1
        counts[prefix][1] += stale

    sitemap = {}
    written = 0
    for rel in pages:
        en_meta, en_body = sources[rel]
        url = url_for(rel)
        versions = [english] + [loc for loc in locales
                                if loc.prefix and (loc.prefix, rel) in resolved]
        if rel != "404.html":
            sitemap[url] = versions
        is_doc = rel.startswith("docs/")

        for loc in locales:
            mode, meta, body, ids = "source", en_meta, en_body, None
            if loc.prefix:
                mode, meta, body, ids = resolved.get(
                    (loc.prefix, rel), ("fallback", en_meta, en_body, None))
            body_loc = english if mode == "fallback" else loc
            body, toc = add_heading_ids(body, anchors=is_doc,
                                        label=body_loc.t("docs.anchor"), ids=ids)
            body = render_body(body, feed_class, feed_style)
            if mode != "fallback":
                body = join_cjk_lines(body)
            if loc.prefix:
                body = localize_links(body, loc, known)
            page = {"loc": loc, "english": english, "locales": locales, "rel": rel,
                    "url": url, "meta": meta, "body": body, "toc": toc, "mode": mode,
                    "versions": [] if rel == "404.html" else versions}
            out = shell(page)
            for old, new in assets.items():
                out = out.replace(old, new)
            base = os.path.join(DIST, loc.prefix) if loc.prefix else DIST
            if rel == "404.html":
                write(os.path.join(base, "404.html"), out)
            else:
                write(os.path.join(base, url.strip("/"), "index.html"), out)
            written += 1

    today = date.today().isoformat()
    entries = []
    for url, versions in sorted(sitemap.items()):
        alternates = ""
        if len(versions) > 1:
            alternates = "".join(
                '<xhtml:link rel="alternate" hreflang="%s" href="%s%s"/>'
                % (v.code, SITE_URL, v.url(url)) for v in versions)
            alternates += ('<xhtml:link rel="alternate" hreflang="x-default" href="%s%s"/>'
                           % (SITE_URL, url))
        for v in versions:
            entries.append("<url><loc>%s%s</loc><lastmod>%s</lastmod>%s</url>"
                           % (SITE_URL, v.url(url), today, alternates))
    write(os.path.join(DIST, "sitemap.xml"),
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" '
          'xmlns:xhtml="http://www.w3.org/1999/xhtml">%s</urlset>' % "".join(entries))
    write(os.path.join(DIST, "robots.txt"),
          "User-agent: *\nAllow: /\n\nSitemap: %s/sitemap.xml\n" % SITE_URL)

    print("built %d pages into %s" % (written, DIST))
    print("translated: %s" % ", ".join(
        "%s %d/%d%s" % (prefix, done, len(pages), " (%d stale)" % stale if stale else "")
        for prefix, (done, stale) in counts.items()))


def print_source_hashes(args):
    targets = args or [os.path.join(PAGES, rel) for rel in collect_pages()]
    status = 0
    for arg in targets:
        candidates = [arg, os.path.join(ROOT, arg), os.path.join(PAGES, arg)]
        path = next((os.path.abspath(c) for c in candidates if os.path.isfile(c)), None)
        if not path or not path.startswith(PAGES + os.sep):
            print("%s: not a page under %s" % (arg, PAGES), file=sys.stderr)
            status = 1
            continue
        rel = os.path.relpath(path, PAGES).replace(os.sep, "/")
        print("source: %s" % source_hash(path) if len(targets) == 1 and args
              else "%s  pages/%s" % (source_hash(path), rel))
    return status


if __name__ == "__main__":
    if "--source-hash" in sys.argv:
        sys.exit(print_source_hashes(sys.argv[sys.argv.index("--source-hash") + 1:]))
    build()
    if "--serve" in sys.argv:
        import http.server
        import functools
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=DIST)
        print("serving http://localhost:8000")
        http.server.HTTPServer(("", 8000), handler).serve_forever()
