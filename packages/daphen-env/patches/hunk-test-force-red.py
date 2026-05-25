#!/usr/bin/env python3
"""
DIAGNOSTIC: force normalizeHighlightedColor to always return red.

If hunk syntax tokens turn bright red after running this + restarting
hunk, the function IS on the rendering path and our reverse-map just
needs to know the hex values Pierre actually emits.

If colors are unchanged, this function isn't on the syntax-rendering
path at all and we need a different attack (registerCustomTheme).

Restore with: cp main.js.bak main.js
"""
import os, sys

p = os.path.expanduser("~/.npm-global/lib/node_modules/hunkdiff/dist/npm/main.js")
s = open(p).read()

old = "function normalizeHighlightedColor(color, theme) {"
new = "function normalizeHighlightedColor(color, theme) { return \"#ff0000\"; if (false) {"

if new in s:
    print(f"OK: already test-patched")
    sys.exit(0)
if old not in s:
    print(f"ERROR: original pattern not found in {p}")
    sys.exit(1)

# Also need to close the extra brace we opened
s2 = s.replace(old, new, 1)
# Find the matching closing brace for normalizeHighlightedColor and add an
# extra brace before it. The function ends with `  return resolvedColor;\n}\n`
# We'll inject the matching brace right before that.
needle = "  return resolvedColor;\n}"
replacement = "  return resolvedColor;\n}\n}"
if needle not in s2:
    print("ERROR: couldn't locate end-of-function anchor")
    sys.exit(1)
s2 = s2.replace(needle, replacement, 1)

if not os.path.exists(p + ".bak"):
    open(p + ".bak", "w").write(s)
open(p, "w").write(s2)
print(f"OK: test-patched {p}; restart hunk")
print(f"   restore with: cp {p}.bak {p}")
