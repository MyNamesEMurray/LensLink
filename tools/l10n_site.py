#!/usr/bin/env python3
"""Checks the website's localization: site/i18n/*.json against en.json, and
every page under site/translations/ against the English page it translates.
Standard library only.

    python3 tools/l10n_site.py

Exits 1 on any error. A stale translation (its `source` hash no longer
matches the English page) is a warning, so editing an English page never
fails CI. See site/README.md.
"""

import collections
import importlib.util
import json
import os
import re
import sys

PLACEHOLDERS = ("{{REPO}}", "{{TESTFLIGHT}}", "{{APPSTORE}}", "{{FEED}}", "{{FEED_STYLE}}")
STRING_PLACEHOLDER = re.compile(r"\{[A-Za-z_][A-Za-z0-9_]*\}|%[sd]")
HREF = re.compile(r'(?<![\w-])href="([^"]*)"')
ID = re.compile(r'(?<![\w-])id="([^"]*)"')
DATA = re.compile(r'(?<![\w-])(data-[\w-]+)="([^"]*)"')
HEADING = re.compile(r"<h([23])[\s>]")
SOURCE = re.compile(r"^[0-9a-f]{12}$")


def load_build(site):
    path = os.path.join(site, "build.py")
    spec = importlib.util.spec_from_file_location("lenslink_site_build", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_json(path, errors, label):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as err:
        errors.append("%s: cannot parse (%s)" % (label, err))
        return None
    if not isinstance(data, dict):
        errors.append("%s: top level must be an object" % label)
        return None
    return data


def check_strings(site, build, errors, warnings):
    i18n = os.path.join(site, "i18n")
    english = load_json(os.path.join(i18n, "en.json"), errors, "i18n/en.json")
    if english is None:
        return
    english = build.flatten(english)

    used = [group for group, _ in build.DOC_ORDER]
    used += [label for _, group in build.DOC_ORDER for _, label in group]
    used += [name for name, _ in build.FOOTER_COLS]
    used += [label for _, links in build.FOOTER_COLS for _, label in links]
    for key in used:
        if key not in english:
            errors.append("i18n/en.json: build.py uses %r, which it does not define" % key)

    prefixes = [prefix for prefix, _, _, _ in build.LANGS if prefix]
    for name in sorted(os.listdir(i18n)):
        stem, ext = os.path.splitext(name)
        if ext != ".json" or (stem != "en" and stem not in prefixes):
            errors.append("i18n/%s: not a known language file (en or %s)"
                          % (name, ", ".join(prefixes)))

    for prefix in prefixes:
        label = "i18n/%s.json" % prefix
        path = os.path.join(i18n, prefix + ".json")
        if not os.path.exists(path):
            warnings.append("%s not found; that language's shell is shown in English" % label)
            continue
        data = load_json(path, errors, label)
        if data is None:
            continue
        data = build.flatten(data)
        missing = [k for k in english if k not in data]
        extra = [k for k in data if k not in english]
        if missing:
            errors.append("%s: missing keys: %s" % (label, ", ".join(missing)))
        if extra:
            errors.append("%s: keys not in en.json: %s" % (label, ", ".join(extra)))
        for key, value in data.items():
            if key not in english:
                continue
            if not isinstance(value, str):
                errors.append("%s: %s must be a string" % (label, key))
                continue
            if not value.strip():
                errors.append("%s: %s is empty" % (label, key))
                continue
            want = collections.Counter(STRING_PLACEHOLDER.findall(english[key]))
            got = collections.Counter(STRING_PLACEHOLDER.findall(value))
            if want != got:
                errors.append("%s: %s has placeholders %s, en.json has %s"
                              % (label, key, sorted(got.elements()) or "none",
                                 sorted(want.elements()) or "none"))


def differences(want, got):
    lost = list((want - got).elements())
    added = list((got - want).elements())
    parts = []
    if lost:
        parts.append("missing %s" % ", ".join(sorted(map(str, lost))))
    if added:
        parts.append("unexpected %s" % ", ".join(sorted(map(str, added))))
    return "; ".join(parts)


def internal_hrefs(body):
    return collections.Counter(h for h in HREF.findall(body) if h.startswith(("/", "#")))


def check_translation(site, build, prefix, rel, path, errors, warnings):
    label = "translations/%s/%s" % (prefix, rel)
    english_path = os.path.join(site, "pages", rel)
    en_meta, en_body = build.read_page(english_path)
    meta, body = build.read_page(path)

    for key in ("title", "description", "source"):
        if not meta.get(key):
            errors.append("%s: front matter needs %s" % (label, key))
    for key, value in en_meta.items():
        if key in ("title", "description"):
            continue
        if meta.get(key) != value:
            errors.append("%s: front matter %s must be %r, as in pages/%s"
                          % (label, key, value, rel))
    for key in meta:
        if key not in en_meta and key != "source":
            errors.append("%s: front matter %s is not in pages/%s" % (label, key, rel))

    source = meta.get("source", "")
    current = build.source_hash(english_path)
    stale = False
    if source and not SOURCE.match(source):
        errors.append("%s: source %r is not 12 hex characters (python3 build.py "
                      "--source-hash pages/%s)" % (label, source, rel))
    elif source and source != current:
        stale = True
        warnings.append("%s is stale: pages/%s is now %s, the translation is of %s"
                        % (label, rel, current, source))
    structural = warnings if stale else errors
    note = " (a warning while the translation is stale)" if stale else ""

    en_levels = HEADING.findall(en_body)
    levels = HEADING.findall(body)
    if levels != en_levels:
        structural.append("%s: h2/h3 headings (%d h2, %d h3) must match pages/%s (%d h2, %d h3) "
                          "in number and order, so anchors stay the same%s"
                          % (label, levels.count("2"), levels.count("3"), rel,
                             en_levels.count("2"), en_levels.count("3"), note))

    checks = [
        ("placeholders",
         collections.Counter({p: en_body.count(p) for p in PLACEHOLDERS if en_body.count(p)}),
         collections.Counter({p: body.count(p) for p in PLACEHOLDERS if body.count(p)})),
        ("internal links", internal_hrefs(en_body), internal_hrefs(body)),
        ("element ids", collections.Counter(set(ID.findall(en_body))),
         collections.Counter(set(ID.findall(body)))),
        ("data attributes",
         collections.Counter('%s="%s"' % pair for pair in DATA.findall(en_body)),
         collections.Counter('%s="%s"' % pair for pair in DATA.findall(body))),
    ]
    for name, want, got in checks:
        if want != got:
            structural.append("%s: %s differ from pages/%s: %s%s"
                              % (label, name, rel, differences(want, got), note))


def check_translations(site, build, errors, warnings):
    root = os.path.join(site, "translations")
    if not os.path.isdir(root):
        return
    prefixes = {prefix for prefix, _, _, _ in build.LANGS if prefix}
    pages = set(build.collect_pages())
    for dirpath, _, filenames in os.walk(root):
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, root).replace(os.sep, "/")
            prefix, _, page = rel.partition("/")
            if prefix not in prefixes:
                errors.append("translations/%s: %s is not a language (%s)"
                              % (rel, prefix, ", ".join(sorted(prefixes))))
            elif page not in pages:
                errors.append("translations/%s: there is no pages/%s to translate" % (rel, page))
            else:
                check_translation(site, build, prefix, page, path, errors, warnings)


def check(repo_root):
    errors, warnings = [], []
    site = os.path.join(repo_root, "site")
    build = load_build(site)
    check_strings(site, build, errors, warnings)
    check_translations(site, build, errors, warnings)
    return errors, warnings


if __name__ == "__main__":
    found_errors, found_warnings = check(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    for message in found_warnings:
        print("warning: %s" % message)
    for message in found_errors:
        print("error: %s" % message)
    print("site: %d errors, %d warnings" % (len(found_errors), len(found_warnings)))
    sys.exit(1 if found_errors else 0)
