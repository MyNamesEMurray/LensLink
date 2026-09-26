#!/usr/bin/env python3
"""Checks every localized surface: the iOS app, the OBS plugin and web
panel, and the website. Standard library only.

    python3 tools/check-l10n.py            # all surfaces
    python3 tools/check-l10n.py ios site   # just these

Exits 1 on any error. Warnings (a stale website translation, a key an OBS
locale file hasn't caught up with) are printed but never fail the run.
See docs/LOCALIZATION.md.
"""

import importlib.util
import os
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(TOOLS)
SURFACES = ["ios", "plugin", "site"]


def load(surface):
    path = os.path.join(TOOLS, "l10n_%s.py" % surface)
    spec = importlib.util.spec_from_file_location("l10n_%s" % surface, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main(argv):
    wanted = argv or SURFACES
    unknown = [s for s in wanted if s not in SURFACES]
    if unknown:
        sys.exit("unknown surface: %s (choose from %s)"
                 % (", ".join(unknown), ", ".join(SURFACES)))
    failed = False
    for surface in wanted:
        errors, warnings = load(surface).check(REPO)
        for w in warnings:
            print("warning: [%s] %s" % (surface, w))
        for e in errors:
            print("error: [%s] %s" % (surface, e))
        print("%s: %d errors, %d warnings" % (surface, len(errors), len(warnings)))
        failed = failed or bool(errors)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
