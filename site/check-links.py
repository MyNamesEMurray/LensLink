#!/usr/bin/env python3
"""Verifies every internal link and #anchor in the built site resolves.

Run after build.py; exits non-zero (and prints each offender) if a link
points at a page or heading that does not exist. External links are not
fetched — this is a build check, not a crawler.
"""

import os
import re
import sys

DIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dist")


def main():
    if not os.path.isdir(DIST):
        sys.exit("dist/ not found — run build.py first")

    pages = {}
    for dirpath, _, filenames in os.walk(DIST):
        for name in filenames:
            if not name.endswith(".html"):
                continue
            path = os.path.join(dirpath, name)
            url = "/" + os.path.relpath(path, DIST).replace(os.sep, "/")
            url = url.replace("/index.html", "/")
            with open(path, encoding="utf-8") as fh:
                pages[url] = fh.read()

    ids = {url: set(re.findall(r'id="([^"]+)"', body))
           for url, body in pages.items()}

    bad = []
    for url, body in pages.items():
        for href in re.findall(r'href="([^"]+)"', body):
            if href.startswith(("http://", "https://", "mailto:")):
                continue
            if href.startswith("#"):
                target, fragment = url, href[1:]
            else:
                target, _, fragment = href.partition("#")
            on_disk = os.path.exists(os.path.join(DIST, target.lstrip("/")))
            if target not in pages and not on_disk:
                bad.append((url, href, "no such page"))
            elif fragment and target in ids and fragment not in ids[target]:
                bad.append((url, href, "no such anchor"))

    for page, href, why in bad:
        print("%s -> %s (%s)" % (page, href, why))
    print("%d pages, %d broken links" % (len(pages), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
