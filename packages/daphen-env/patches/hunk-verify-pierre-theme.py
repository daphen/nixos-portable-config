#!/usr/bin/env python3
"""Verify whether the in-memory parsed Pierre theme reflects our hex
substitutions. If it does but rendering still shows Pierre defaults,
the theme isn't being consumed from this JSON literal at all."""
import json
import os
import re
import sys

p = os.path.expanduser("~/.npm-global/lib/node_modules/hunkdiff/dist/npm/main.js")
src = open(p).read()
m = re.search(
    r"pierre_dark_default\s*=\s*Object\.freeze\(JSON\.parse\('(.*?)'\)\)",
    src,
    re.DOTALL,
)
if not m:
    print("ERROR: pierre_dark_default not found")
    sys.exit(1)

# Unescape the JS-string literal back to JSON text. JS uses \\ for a
# literal backslash inside single-quoted strings; Python's
# unicode_escape handles that pattern.
raw = m.group(1).encode().decode("unicode_escape")
j = json.loads(raw)

print("semantic.keyword: ", j["semanticTokenColors"]["keyword"])
print("semantic.string:  ", j["semanticTokenColors"]["string"])
print("semantic.function:", j["semanticTokenColors"]["function"])
print("semantic.type:    ", j["semanticTokenColors"]["type"])
print("semantic.comment: ", j["semanticTokenColors"]["comment"])
print("semantic.number:  ", j["semanticTokenColors"]["number"])
print("editor.fg:        ", j["colors"]["editor.foreground"])
print()

# Also list any other Pierre theme files shipped under @pierre/diffs
# or @pierre/theme that might be consumed instead.
import subprocess
pierre_root = os.path.expanduser("~/.npm-global/lib/node_modules/hunkdiff/node_modules/@pierre")
if os.path.isdir(pierre_root):
    res = subprocess.run(
        ["grep", "-rl", "tokenColors", pierre_root],
        capture_output=True, text=True,
    )
    print("files with tokenColors under @pierre:")
    for line in res.stdout.strip().splitlines():
        print("  ", line)
