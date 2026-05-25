#!/usr/bin/env python3
"""
Expand hunkdiff's RESERVED_PIERRE_TOKEN_COLORS reverse-map so all 9
[custom_theme.syntax] keys (keyword, string, comment, number, function,
property, type, punctuation, default) actually flow through to the
renderer. By default hunk only maps 2 entries (keyword + string), which
means the rest of Pierre's hardcoded syntax colors leak through even
when a custom theme overrides them.

Idempotent: bails cleanly if the file is already patched or doesn't
contain the expected pattern (different hunkdiff version).
"""
import os
import sys

p = os.path.expanduser("~/.npm-global/lib/node_modules/hunkdiff/dist/npm/main.js")
if not os.path.isfile(p):
    print(f"ERROR: hunkdiff not installed at {p}")
    sys.exit(1)

s = open(p).read()

old = """var RESERVED_PIERRE_TOKEN_COLORS = {
  dark: {
    "#ff6762": "keyword",
    "#5ecc71": "string"
  },
  light: {
    "#d52c36": "keyword",
    "#199f43": "string"
  }
};"""

new = """var RESERVED_PIERRE_TOKEN_COLORS = {
  dark: {
    "#ff6762": "keyword",
    "#ff678d": "keyword",
    "#5ecc71": "string",
    "#84848a": "comment",
    "#68cdf2": "number",
    "#ffa359": "property",
    "#9d6afb": "function",
    "#d568ea": "type",
    "#79797f": "punctuation"
  },
  light: {
    "#d52c36": "keyword",
    "#fc2b73": "keyword",
    "#199f43": "string",
    "#84848a": "comment",
    "#1ca1c7": "number",
    "#d47628": "property",
    "#7b43f8": "function",
    "#c635e4": "type",
    "#79797f": "punctuation"
  }
};"""

if new in s:
    print(f"OK: already patched ({p})")
    sys.exit(0)
if old not in s:
    print(f"ERROR: original pattern not found in {p}")
    print("Either hunkdiff version differs or has been modified in another way.")
    sys.exit(1)

open(p + ".bak", "w").write(s)
open(p, "w").write(s.replace(old, new, 1))
print(f"OK: patched {p}")
print(f"     backup at {p}.bak")
