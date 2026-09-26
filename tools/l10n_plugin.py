#!/usr/bin/env python3

import os
import re
import sys

BASE_LOCALE = "en-US.ini"
LOCALE_DIR = os.path.join("obs-plugin", "data", "locale")
SRC_DIR = os.path.join("obs-plugin", "src")
WEB_FILE = "web-control.c"
WEB_ARRAY = "web_text_keys"
WEB_PREFIX = "Web."

KEY_RE = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.\-]*$")
LOOKUP_LITERAL_RE = re.compile(
    r'\b(?:T_|obs_module_text)\(\s*"((?:[^"\\\n]|\\.)*)"\s*\)')
LOOKUP_MACRO_RE = re.compile(
    r"\b(?:T_|obs_module_text)\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)")
DEFINE_RE = re.compile(
    r'^[ \t]*#[ \t]*define[ \t]+([A-Za-z_][A-Za-z0-9_]*)[ \t]+"((?:[^"\\\n]|\\.)*)"[ \t]*$',
    re.M)
WEB_ARRAY_RE = re.compile(
    r"\b" + WEB_ARRAY + r"\s*\[\s*\]\s*=\s*\{(.*?)\};", re.S)
STRING_RE = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
PAGE_ATTR_RE = re.compile(r"\bdata-t(?:-title)?='([^']+)'")
PAGE_CALL_RE = re.compile(r"(?<![A-Za-z0-9_$.])t\('([^']+)'\)")


def parse_ini(path, rel, errors, warnings):
    entries = {}
    try:
        raw = open(path, "rb").read()
    except OSError as exc:
        errors.append(f"{rel}: cannot read ({exc})")
        return entries
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        errors.append(f"{rel}: not valid UTF-8 ({exc})")
        return entries
    if text.startswith("﻿"):
        warnings.append(f"{rel}:1: UTF-8 byte-order mark (save without BOM)")
        text = text[1:]

    for n, line in enumerate(text.split("\n"), 1):
        if line.endswith("\r"):
            line = line[:-1]
        stripped = line.strip()
        if not stripped or stripped[0] in "#;":
            continue
        eq = line.find("=")
        if eq <= 0:
            errors.append(f"{rel}:{n}: malformed line (expected Key=\"Value\")")
            continue
        key, rest = line[:eq], line[eq + 1:]
        if not KEY_RE.match(key):
            errors.append(f"{rel}:{n}: malformed key {key!r}")
            continue
        if len(rest) < 2 or rest[0] != '"' or rest[-1] != '"':
            errors.append(
                f"{rel}:{n}: {key}: value must be wrapped in double quotes "
                f"with nothing after the closing quote")
            continue
        value = rest[1:-1]
        if '"' in value:
            errors.append(
                f"{rel}:{n}: {key}: bare double quote inside the value "
                f"(use ' or typographic quotes)")
            continue
        if key in entries:
            errors.append(
                f"{rel}:{n}: duplicate key {key} "
                f"(first on line {entries[key][1]})")
            continue
        entries[key] = (value, n)
    return entries


def strip_comments(src):
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c in "\"'":
            j = i + 1
            while j < n and src[j] != c and src[j] != "\n":
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1])
            i = j + 1
        elif src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
        elif src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def line_of(text, offset):
    return text.count("\n", 0, offset) + 1


def used_keys(repo_root, errors):
    src_dir = os.path.join(repo_root, SRC_DIR)
    used = {}

    def add(key, where):
        used.setdefault(key, []).append(where)

    for name in sorted(os.listdir(src_dir)):
        if not name.endswith((".c", ".cpp", ".h")):
            continue
        rel = os.path.join(SRC_DIR, name)
        text = strip_comments(
            open(os.path.join(src_dir, name), encoding="utf-8").read())

        macros = {}
        for m in DEFINE_RE.finditer(text):
            macros.setdefault(m.group(1), []).append(m.group(2))

        for m in LOOKUP_LITERAL_RE.finditer(text):
            add(m.group(1), f"{rel}:{line_of(text, m.start())}")

        for m in LOOKUP_MACRO_RE.finditer(text):
            ident = m.group(1)
            line_start = text.rfind("\n", 0, m.start()) + 1
            if text[line_start:m.start()].lstrip().startswith("#"):
                continue
            where = f"{rel}:{line_of(text, m.start())}"
            if ident in macros:
                for value in macros[ident]:
                    add(value, where)
            elif ident.isupper():
                errors.append(
                    f"{where}: cannot resolve key macro {ident} "
                    f"(no #define {ident} \"…\" in this file)")

        if name == WEB_FILE:
            arr = WEB_ARRAY_RE.search(text)
            if not arr:
                errors.append(f"{rel}: {WEB_ARRAY}[] not found")
                continue
            base = arr.start(1)
            exported = set()
            for m in STRING_RE.finditer(arr.group(1)):
                key = m.group(1)
                where = f"{rel}:{line_of(text, base + m.start())}"
                if not key.startswith(WEB_PREFIX):
                    errors.append(
                        f"{where}: {WEB_ARRAY} entry {key} lacks the "
                        f"{WEB_PREFIX} prefix")
                if key in exported:
                    errors.append(f"{where}: {key} listed twice in {WEB_ARRAY}")
                exported.add(key)
                add(key, where)
            referenced = set()
            for rx in (PAGE_ATTR_RE, PAGE_CALL_RE):
                for m in rx.finditer(text):
                    key = WEB_PREFIX + m.group(1)
                    referenced.add(key)
                    if key not in exported:
                        errors.append(
                            f"{rel}:{line_of(text, m.start())}: the page "
                            f"uses {m.group(1)!r} but {key} is not in "
                            f"{WEB_ARRAY}")
            for key in sorted(exported - referenced):
                errors.append(
                    f"{rel}: {key} is exported in {WEB_ARRAY} but the page "
                    f"never uses it")
    return used


def check(repo_root: str) -> tuple[list[str], list[str]]:
    errors: list[str] = []
    warnings: list[str] = []
    locale_dir = os.path.join(repo_root, LOCALE_DIR)

    base_path = os.path.join(locale_dir, BASE_LOCALE)
    if not os.path.isfile(base_path):
        return [f"{os.path.join(LOCALE_DIR, BASE_LOCALE)}: missing"], warnings

    def rel(p):
        return os.path.relpath(p, repo_root)

    base = parse_ini(base_path, rel(base_path), errors, warnings)

    for key, (value, n) in base.items():
        if not value:
            errors.append(f"{rel(base_path)}:{n}: {key}: empty value")

    used = used_keys(repo_root, errors)
    for key in sorted(used):
        if key not in base:
            errors.append(
                f"{used[key][0]}: key {key} is missing from {BASE_LOCALE}")
    for key, (_, n) in sorted(base.items(), key=lambda kv: kv[1][1]):
        if key not in used:
            errors.append(
                f"{rel(base_path)}:{n}: {key} is not used by obs-plugin/src")

    for name in sorted(os.listdir(locale_dir)):
        if not name.endswith(".ini") or name == BASE_LOCALE:
            continue
        path = os.path.join(locale_dir, name)
        r = rel(path)
        entries = parse_ini(path, r, errors, warnings)
        for key, (value, n) in entries.items():
            if key not in base:
                errors.append(f"{r}:{n}: {key} is not a key in {BASE_LOCALE}")
                continue
            if not value.strip():
                errors.append(f"{r}:{n}: {key}: empty value")
                continue
            en = base[key][0]
            if en and (en[0].isspace() != value[0].isspace()):
                errors.append(
                    f"{r}:{n}: {key}: leading space differs from "
                    f"{BASE_LOCALE} (the value is concatenated with other "
                    f"text)")
            if en and (en[-1].isspace() != value[-1].isspace()):
                errors.append(
                    f"{r}:{n}: {key}: trailing space differs from "
                    f"{BASE_LOCALE} (the value is concatenated with other "
                    f"text)")
        missing = [k for k in base if k not in entries]
        if missing:
            warnings.append(
                f"{r}: {len(missing)} of {len(base)} keys untranslated "
                f"(OBS shows English for them): " + ", ".join(missing))
    return errors, warnings


def main(argv):
    root = argv[1] if len(argv) > 1 else os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))
    errors, warnings = check(root)
    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}")
    print(f"l10n_plugin: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
