#!/usr/bin/env python3
"""Checks the Stream Deck plugin's localization: every <locale>.json beside
the manifest must have exactly the keys of en.json. Standard library only.

    python3 tools/l10n_streamdeck.py

Exits 1 on any error. See docs/LOCALIZATION.md.
"""

import glob
import json
import os
import sys

PLUGIN_DIR = os.path.join("streamdeck", "cam.lenslink.streamdeck.sdPlugin")
BASE = "en.json"


def flatten(node, prefix=""):
    if isinstance(node, dict):
        for key, value in node.items():
            yield from flatten(value, f"{prefix}{key}.")
    else:
        yield prefix[:-1], node


def load(path, errors):
    try:
        with open(path, encoding="utf-8") as fh:
            return dict(flatten(json.load(fh)))
    except (OSError, ValueError) as e:
        errors.append(f"{path}: {e}")
        return None


def check(repo_root):
    errors, warnings = [], []
    plugin = os.path.join(repo_root, PLUGIN_DIR)
    base = load(os.path.join(plugin, BASE), errors)
    if base is None:
        return errors, warnings
    for key, value in base.items():
        if not value:
            errors.append(f"{PLUGIN_DIR}/{BASE}: {key}: empty value")
    for path in sorted(glob.glob(os.path.join(plugin, "*.json"))):
        name = os.path.basename(path)
        if name in (BASE, "manifest.json"):
            continue
        keys = load(path, errors)
        if keys is None:
            continue
        for key in sorted(base.keys() - keys.keys()):
            errors.append(f"{PLUGIN_DIR}/{name}: missing key {key}")
        for key in sorted(keys.keys() - base.keys()):
            errors.append(f"{PLUGIN_DIR}/{name}: key {key} is not in {BASE}")
        for key in sorted(k for k, v in keys.items() if not v):
            errors.append(f"{PLUGIN_DIR}/{name}: {key}: empty value")
    return errors, warnings


if __name__ == "__main__":
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    errs, warns = check(root)
    for line in warns + errs:
        print(line)
    sys.exit(1 if errs else 0)
