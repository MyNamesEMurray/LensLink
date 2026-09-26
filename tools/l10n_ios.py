#!/usr/bin/env python3
import bisect
import os
import re
import sys
from dataclasses import dataclass

VIEW_CALLS = {"Text", "Button", "Toggle", "Label", "Picker", "Section", "DisclosureGroup",
              "Link", "Menu", "Stepper", "TextField", "ProgressView"}
MODIFIER_CALLS = {"navigationTitle", "accessibilityLabel", "accessibilityHint",
                  "accessibilityValue", "help", "alert", "confirmationDialog"}
KEY_CALLS = {"IntentDescription", "LocalizedStringKey"}
STRINGS_FILES = ("Localizable.strings", "InfoPlist.strings", "AppShortcuts.strings")
SPEC_RE = re.compile(r"%(?:(\d+)\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?"
                     r"(hh|h|ll|l|q|L|z|t|j)?([@dDiuUxXoOfFeEgGaAcCsSp%])")
SWIFT_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "'": "'", "\\": "\\"}
PLIST_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "a": "\a", "b": "\b", "f": "\f",
                 "v": "\v", '"': '"', "'": "'", "\\": "\\"}
STRINGS_TOKEN = re.compile(r'\s+|/\*.*?\*/|//[^\n]*|"(?:[^"\\]|\\.)*"|[=;]', re.S)
IDENT_RE = re.compile(r"[A-Za-z_]\w*")
NUMBER_RE = re.compile(r"\d[\w.]*")


class SwiftSyntaxError(Exception):
    pass


@dataclass
class Tok:
    kind: str
    value: str
    pos: int
    raw: bool = False
    interp: bool = False
    source: str = ""


def skip_comment(src, i):
    if src.startswith("//", i):
        end = src.find("\n", i)
        return len(src) if end < 0 else end
    depth = 0
    for m in re.finditer(r"/\*|\*/", src[i:]):
        depth += 1 if m.group() == "/*" else -1
        if depth == 0:
            return i + m.end()
    raise SwiftSyntaxError("unterminated block comment")


def scan_string(src, i):
    start = i
    while src[i] == "#":
        i += 1
    hashes = i - start
    multiline = src.startswith('"""', i)
    i += 3 if multiline else 1
    close, esc = ('"""' if multiline else '"') + "#" * hashes, "\\" + "#" * hashes
    out, interp = [], False
    while not src.startswith(close, i):
        if i >= len(src) or (src[i] == "\n" and not multiline):
            raise SwiftSyntaxError(f"unterminated string literal at offset {start}")
        if not src.startswith(esc, i):
            out.append(src[i])
            i += 1
            continue
        j = i + len(esc)
        c = src[j]
        if c == "(":
            interp = True
            _, k = tokenize(src, j, nested=True)
            out.append(src[i:k])
            i = k
        elif c == "u" and src[j + 1] == "{":
            k = src.index("}", j)
            out.append(chr(int(src[j + 2:k], 16)))
            i = k + 1
        elif c in SWIFT_ESCAPES or (multiline and c == "\n"):
            out.append(SWIFT_ESCAPES.get(c, ""))
            i = j + 1
        else:
            raise SwiftSyntaxError(f"bad escape \\{c} at offset {i}")
    end = i + len(close)
    return end, Tok("str", "".join(out), start, raw=hashes > 0 or multiline,
                    interp=interp, source=src[start:end])


def tokenize(src, i=0, nested=False):
    toks, depth = [], 0
    while i < len(src):
        c = src[i]
        if src.startswith(("//", "/*"), i):
            i = skip_comment(src, i)
        elif c == '"' or re.match(r'#+"', src[i:i + 8]):
            i, tok = scan_string(src, i)
            toks.append(tok)
        elif c.isalpha() or c == "_" or c.isdigit():
            m = (NUMBER_RE if c.isdigit() else IDENT_RE).match(src, i)
            toks.append(Tok("num" if c.isdigit() else "ident", m.group(), i))
            i = m.end()
        elif c.isspace():
            i += 1
        else:
            if nested and c in "()":
                depth += 1 if c == "(" else -1
                if depth == 0:
                    return toks, i + 1
            toks.append(Tok("punct", c, i))
            i += 1
    if nested:
        raise SwiftSyntaxError("unbalanced string interpolation")
    return toks, i


def is_punct(tok, value):
    return tok is not None and tok.kind == "punct" and tok.value == value


def split_args(toks, open_idx):
    args, current, depth = [], [], 0
    for t in toks[open_idx + 1:]:
        if t.kind == "punct" and t.value in "([{":
            depth += 1
        elif t.kind == "punct" and t.value in ")]}":
            if depth == 0:
                return args + [current] if current or args else args
            depth -= 1
        elif is_punct(t, ",") and depth == 0:
            args.append(current)
            current = []
            continue
        current.append(t)
    return args


def top_level(arg):
    depth = 0
    for t in arg:
        depth -= t.kind == "punct" and t.value in ")]}"
        if depth == 0:
            yield t
        depth += t.kind == "punct" and t.value in "([{"


def parse_specs(text):
    specs, i = [], text.find("%")
    while i >= 0:
        m = SPEC_RE.match(text, i)
        if not m:
            raise ValueError(f"invalid format specifier {text[i:i + 6]!r}")
        if m.group(3) != "%":
            conv = m.group(3)
            family = "f" if conv in "fFeEgGaA" else "d" if conv in "di" else conv
            length = "ll" if m.group(2) == "q" else (m.group(2) or "")
            specs.append((int(m.group(1)) if m.group(1) else None, length + family))
        i = text.find("%", m.end())
    return specs


def check_format_key(key, nargs, loc, errors):
    try:
        specs = parse_specs(key)
    except ValueError as e:
        return errors.append(f"{loc}: {e} in {key!r}")
    positional = [p for p, _ in specs if p is not None]
    if len(specs) >= 2 and len(positional) != len(specs):
        errors.append(f"{loc}: {key!r} has 2+ arguments and needs positional specifiers")
    if nargs == 0 and "%" in key:
        errors.append(f"{loc}: '%' in an L() key without arguments; pass the value as an argument")
    elif nargs is not None and nargs and (max(positional) if positional else len(specs)) != nargs:
        errors.append(f"{loc}: {key!r} does not match the {nargs} argument(s) given to L()")


def extract_swift(path, rel):
    src = open(path, encoding="utf-8").read()
    newlines = [m.start() for m in re.finditer("\n", src)]
    where = lambda tok: f"{rel}:{bisect.bisect_right(newlines, tok.pos) + 1}"
    keys, errors, warnings, phrases = {}, [], [], []
    try:
        toks, _ = tokenize(src)
    except SwiftSyntaxError as e:
        return keys, [f"{rel}: {e}"], warnings, phrases

    def add_key(lit, kind, nargs=None):
        if lit.raw:
            errors.append(f"{where(lit)}: raw/multiline literal in a localizing position")
        elif lit.interp:
            errors.append(f"{where(lit)}: interpolation inside localized literal {lit.source}")
        elif kind == "swiftui" and "%" in lit.value:
            errors.append(f"{where(lit)}: '%' in a SwiftUI literal key; use L() with a format key")
        elif lit.value:
            keys.setdefault(lit.value, where(lit))
            if kind == "L":
                check_format_key(lit.value, nargs, where(lit), errors)

    for idx, tok in enumerate(toks):
        prev = toks[idx - 1] if idx else None
        nxt = toks[idx + 1] if idx + 1 < len(toks) else None
        name = tok.value if tok.kind == "ident" else None
        if name == "phrases" and is_punct(nxt, ":"):
            for t in toks[idx + 3:]:
                if is_punct(t, "]"):
                    break
                if t.kind == "str":
                    phrases.append(re.sub(r"\\\(\s*\.applicationName\s*\)",
                                          "${applicationName}", t.value))
        if name == "LocalizedStringResource" and is_punct(nxt, "="):
            if idx + 2 < len(toks) and toks[idx + 2].kind == "str":
                add_key(toks[idx + 2], "resource")
        if not name or not is_punct(nxt, "(") or (prev and prev.value == "func"):
            continue
        if name in MODIFIER_CALLS and is_punct(prev, "."):
            kind = "swiftui"
        elif name in VIEW_CALLS and not is_punct(prev, "."):
            kind = "swiftui"
        elif name in KEY_CALLS or (name == "L" and not is_punct(prev, ".")):
            kind = name if name == "L" else "key"
        else:
            continue
        args = split_args(toks, idx + 1)
        first = args[0] if args else []
        if len(first) >= 2 and first[0].kind == "ident" and is_punct(first[1], ":"):
            if kind == "L":
                errors.append(f"{where(tok)}: L() takes an unlabeled string literal")
        elif len(first) == 1 and first[0].kind == "str":
            add_key(first[0], kind, len(args) - 1)
        elif kind == "L":
            errors.append(f"{where(tok)}: L() needs a plain string literal as its first argument")
        else:
            level = list(top_level(first))
            bare = [t for t in level if t.kind == "str"]
            if bare and any(is_punct(t, "?") for t in level):
                errors.append(f"{where(bare[0])}: bare string literal in a conditional passed "
                              f"to {name}(); wrap each branch in L()")
            elif bare:
                warnings.append(f"{where(bare[0])}: string literal inside an expression passed "
                                f"to {name}() is not localized")
    return keys, errors, warnings, phrases


def unescape(body):
    def repl(m):
        e = m.group(1)
        if len(e) == 5:
            return chr(int(e[1:], 16))
        if len(e) == 3:
            return chr(int(e, 8))
        if e in PLIST_ESCAPES:
            return PLIST_ESCAPES[e]
        raise ValueError(f"invalid escape \\{e}")
    return re.sub(r"\\(U[0-9a-fA-F]{4}|[0-7]{3}|.)", repl, body, flags=re.S)


def parse_strings(path, rel):
    try:
        text = open(path, "rb").read().decode("utf-8").lstrip("﻿")
    except UnicodeDecodeError as e:
        return {}, [f"{rel}: not valid UTF-8 ({e})"], []
    entries, pending, commented, step, i = [], [], False, 0, 0
    expected = ('"', "=", '"', ";")
    while i < len(text):
        line = text.count("\n", 0, i) + 1
        m = STRINGS_TOKEN.match(text, i)
        if not m:
            return {}, [f"{rel}:{line}: syntax error near {text[i:i + 12]!r}"], []
        tok, i = m.group(), m.end()
        if tok[0].isspace() or tok[0] == "/":
            commented = commented or tok[0] == "/"
            continue
        if tok[0] != expected[step]:
            return {}, [f"{rel}:{line}: expected {expected[step]!r}, found {tok[:12]!r}"], []
        if tok[0] == '"':
            try:
                pending.append((unescape(tok[1:-1]), line))
            except ValueError as e:
                return {}, [f"{rel}:{line}: {e}"], []
        step = (step + 1) % 4
        if step == 0:
            entries.append((pending[0][0], pending[1][0], pending[0][1], commented))
            pending, commented = [], False
    if step:
        return {}, [f"{rel}: unexpected end of file"], []
    table, errors = {}, []
    for key, value, line, _ in entries:
        if key in table:
            errors.append(f"{rel}:{line}: duplicate key {key!r}")
        table[key] = value
    return table, errors, entries


def read_targets(project_path):
    targets, current, section = {}, None, None
    for line in open(project_path, encoding="utf-8").read().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            section, current = stripped.rstrip(":"), None
        elif section == "targets" and indent == 2 and stripped.endswith(":"):
            current = targets.setdefault(stripped[:-1], {"sources": [], "usage": {}, "lines": []})
        elif section == "targets" and current is not None:
            current["lines"].append((indent, stripped))
    for target in targets.values():
        lines, in_sources = target.pop("lines"), False
        for k, (indent, stripped) in enumerate(lines):
            if indent == 4:
                in_sources = stripped == "sources:"
            elif in_sources and stripped.startswith("- "):
                entry = re.sub(r"^path:\s*", "", stripped[2:].strip())
                target["sources"].append(entry.strip("'\""))
            m = re.match(r"(NS\w+UsageDescription):\s*(.*)$", stripped)
            if m:
                value = m.group(2).strip()
                if value in (">-", ">"):
                    parts = []
                    for sub_indent, sub in lines[k + 1:]:
                        if sub_indent <= indent:
                            break
                        parts.append(sub)
                    value = " ".join(parts)
                target["usage"][m.group(1)] = value.strip("'\"")
    return targets


def target_files(app_root, sources):
    swift, dirs = set(), []
    for entry in sources:
        path = os.path.join(app_root, entry)
        if os.path.isdir(path):
            dirs.append(path)
            for root, subdirs, files in os.walk(path):
                subdirs[:] = [d for d in subdirs if not d.endswith(".lproj")]
                swift.update(os.path.join(root, f) for f in files if f.endswith(".swift"))
        elif path.endswith(".swift"):
            swift.add(path)
    en_dirs = [os.path.join(root, "en.lproj") for d in dirs
               for root, subdirs, _ in os.walk(d) if "en.lproj" in subdirs]
    return sorted(swift), (en_dirs[0] if en_dirs else None)


def check_translation(path, rel, fname, en_table, errors):
    if not os.path.exists(path):
        return errors.append(f"{rel}: missing (en.lproj has {fname})")
    table, errs, _ = parse_strings(path, rel)
    if errs:
        return errors.extend(errs)
    errors += [f"{rel}: missing key {k!r}" for k in sorted(set(en_table) - set(table))]
    errors += [f"{rel}: key {k!r} is not in en.lproj" for k in sorted(set(table) - set(en_table))]
    for key in sorted(set(table) & set(en_table)):
        value = table[key]
        if not value:
            errors.append(f"{rel}: empty value for {key!r}")
        elif fname == "AppShortcuts.strings" and "${applicationName}" not in value:
            errors.append(f"{rel}: {key!r} value lacks ${{applicationName}}")
        try:
            if sorted(t for _, t in parse_specs(value)) != sorted(t for _, t in parse_specs(key)):
                errors.append(f"{rel}: format specifiers differ from en for {key!r}")
        except ValueError as e:
            errors.append(f"{rel}: {e} in the value for {key!r}")


def check_target(name, target, keys, phrases, en_dir, rel, errors, warnings):
    en = {}
    for fname in STRINGS_FILES:
        path = os.path.join(en_dir, fname)
        if not os.path.exists(path):
            continue
        en[fname], errs, entries = parse_strings(path, rel(path))
        errors += errs
        for key, value, line, commented in entries:
            if not value:
                errors.append(f"{rel(path)}:{line}: empty value for {key!r}")
            if not commented and fname == "Localizable.strings":
                warnings.append(f"{rel(path)}:{line}: no translator comment for {key!r}")
    where = lambda fname: rel(os.path.join(en_dir, fname))
    table, info, shortcuts = (en.get(f) for f in STRINGS_FILES)
    if (keys and table is None) or (target["usage"] and info is None) or (phrases and shortcuts is None):
        errors.append(f"{rel(en_dir)}: missing .strings files for target {name}")
    table, info, shortcuts = table or {}, info or {}, shortcuts or {}
    loc = where("Localizable.strings")
    errors += [f"{keys[k]}: key {k!r} missing from {loc}" for k in sorted(set(keys) - set(table))]
    errors += [f"{loc}: unused key {k!r} (no {name} source uses it)"
               for k in sorted(set(table) - set(keys))]
    errors += [f"{loc}: en value differs from key {k!r}" for k, v in sorted(table.items()) if v != k]
    for key in sorted(k for k in table if "%" in k):
        check_format_key(key, None, loc, errors)
    for key in sorted(set(info) | set(target["usage"])):
        if info.get(key) != target["usage"].get(key):
            errors.append(f"{where('InfoPlist.strings')}: {key} does not match project.yml")
    for key in sorted(set(phrases) | set(shortcuts)):
        if key not in phrases or shortcuts.get(key) != key or "${applicationName}" not in key:
            errors.append(f"{where('AppShortcuts.strings')}: {key!r} does not match the Swift phrases")
    parent = os.path.dirname(en_dir)
    for lang in sorted(os.listdir(parent)):
        lang_dir = os.path.join(parent, lang)
        if not lang.endswith(".lproj") or lang in ("en.lproj", "Base.lproj"):
            continue
        for fname, en_table in sorted(en.items()):
            path = os.path.join(lang_dir, fname)
            check_translation(path, rel(path), fname, en_table, errors)
        for extra in sorted(set(os.listdir(lang_dir)) - set(en)):
            if extra.endswith(".strings"):
                errors.append(f"{rel(os.path.join(lang_dir, extra))}: not in en.lproj")


def check(repo_root):
    errors, warnings, cache = [], [], {}
    app_root = os.path.join(repo_root, "ios-app")
    rel = lambda p: os.path.relpath(p, repo_root)
    for name, target in sorted(read_targets(os.path.join(app_root, "project.yml")).items()):
        files, en_dir = target_files(app_root, target["sources"])
        keys, phrases = {}, []
        for path in files:
            if path not in cache:
                cache[path] = extract_swift(path, rel(path))
                errors += cache[path][1]
                warnings += cache[path][2]
            for key, loc in cache[path][0].items():
                keys.setdefault(key, loc)
            phrases += cache[path][3]
        if en_dir is None:
            errors.append(f"target {name}: no en.lproj under its sources")
        else:
            check_target(name, target, keys, phrases, en_dir, rel, errors, warnings)
    return errors, warnings


if __name__ == "__main__":
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))
    errs, warns = check(root)
    for w in warns:
        print(f"warning: {w}")
    for e in errs:
        print(f"error: {e}")
    print(f"l10n_ios: {len(errs)} error(s), {len(warns)} warning(s)")
    sys.exit(1 if errs else 0)
