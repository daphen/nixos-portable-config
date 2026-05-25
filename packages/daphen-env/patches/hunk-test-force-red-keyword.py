#!/usr/bin/env python3
"""DIAGNOSTIC: force the `keyword` syntax style to bright red inside
createSyntaxStyle, while leaving everything else alone. If keywords
turn red, syntaxStyle IS the active theming surface and we know where
to plug user colors in. If keywords stay normal, syntaxStyle isn't
consumed during diff rendering and the path lives elsewhere entirely.

Restore with: cp main.js.bak main.js
"""
import os, sys
p = os.path.expanduser("~/.npm-global/lib/node_modules/hunkdiff/dist/npm/main.js")
s = open(p).read()
old = 'keyword: { fg: RGBA.fromHex(colors.keyword), bold: true },'
new = 'keyword: { fg: RGBA.fromHex("#ff0000"), bold: true },'
if new in s:
    print("OK: already test-patched")
    sys.exit(0)
if old not in s:
    print("ERROR: original pattern not found")
    sys.exit(1)
if not os.path.exists(p + ".bak"):
    open(p + ".bak", "w").write(s)
open(p, "w").write(s.replace(old, new, 1))
print("OK: test-patched keyword style to red")
print("restart hunk: pkill -f hunk; hunkr")
