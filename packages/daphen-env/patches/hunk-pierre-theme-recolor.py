#!/usr/bin/env python3
"""
Rewrite the hex values inside hunk's bundled Pierre Dark/Light Shiki
themes so they emit colors from the user's [custom_theme.syntax] in
~/.config/hunk/config.toml. This uses Pierre's *real* theming layer
(Shiki tokenColors / semanticTokenColors), not the limited 9-key
RESERVED_PIERRE_TOKEN_COLORS reverse-map.

Approach: find the `pierre_dark_default = Object.freeze(JSON.parse('...'))`
literal, do hex-level substitution inside the JSON string per a mapping
from Pierre's hardcoded hex to the corresponding palette key, then
write back. Same for pierre_light_default.

Idempotent: bails if [custom_theme.syntax] missing, or if the literal
isn't found.
"""
import os
import re
import sys

try:
    import tomllib
except ImportError:
    import tomli as tomllib  # type: ignore

MAIN_JS = os.path.expanduser("~/.npm-global/lib/node_modules/hunkdiff/dist/npm/main.js")
CONFIG = os.path.expanduser("~/.config/hunk/config.toml")

# Pierre's hardcoded hex values, mapped to one of the 9 keys in
# [custom_theme.syntax]: default, keyword, string, comment, number,
# function, property, type, punctuation.
DARK_MAP = {
    "#84848a": "comment",
    "#5ecc71": "string",
    "#68cdf2": "number",
    "#ff678d": "keyword",
    "#ff6762": "keyword",
    "#ffa359": "property",
    "#9d6afb": "function",
    "#d568ea": "type",
    "#79797f": "punctuation",
    "#ffd452": "number",
    "#ffca00": "keyword",
    "#08c0ef": "punctuation",
    "#adadb1": "default",
    "#64d1db": "string",
    "#fbfbfb": "default",
}

LIGHT_MAP = {
    "#84848a": "comment",
    "#199f43": "string",
    "#1ca1c7": "number",
    "#fc2b73": "keyword",
    "#d52c36": "keyword",
    "#d47628": "property",
    "#7b43f8": "function",
    "#c635e4": "type",
    "#79797f": "punctuation",
    "#d5a910": "number",
    "#d5901c": "keyword",
    "#08c0ef": "punctuation",
    "#070707": "default",
    "#17a5af": "string",
}


def load_syntax():
    if not os.path.isfile(CONFIG):
        print(f"ERROR: hunk config not found at {CONFIG}")
        sys.exit(1)
    with open(CONFIG, "rb") as f:
        cfg = tomllib.load(f)
    syntax = cfg.get("custom_theme", {}).get("syntax", {})
    required = ["default", "keyword", "string", "comment", "number",
                "function", "property", "type", "punctuation"]
    missing = [k for k in required if k not in syntax]
    if missing:
        print(f"ERROR: [custom_theme.syntax] missing keys: {missing}")
        sys.exit(1)
    return {k: v.lower() for k, v in syntax.items()}


def patch_block(src: str, marker: str, hex_map: dict, syntax: dict) -> tuple[str, int]:
    pattern = re.compile(
        rf"({re.escape(marker)}\s*=\s*Object\.freeze\(JSON\.parse\(')(.*?)('\)\);)",
        re.DOTALL,
    )
    m = pattern.search(src)
    if not m:
        return src, 0
    prefix, body, suffix = m.groups()
    new_body = body
    n = 0
    for pierre_hex, key in hex_map.items():
        user_hex = syntax[key]
        # case-insensitive replace: Pierre uses both #ff678d and #FF678D etc.
        ci_pattern = re.compile(re.escape(pierre_hex), re.IGNORECASE)
        new_body, count = ci_pattern.subn(user_hex, new_body)
        n += count
    new_src = src[:m.start()] + prefix + new_body + suffix + src[m.end():]
    return new_src, n


def main() -> int:
    if not os.path.isfile(MAIN_JS):
        print(f"ERROR: hunkdiff not at {MAIN_JS}")
        return 1
    syntax = load_syntax()
    print(f"loaded [custom_theme.syntax]: {syntax}")

    src = open(MAIN_JS).read()

    if not os.path.exists(MAIN_JS + ".bak"):
        open(MAIN_JS + ".bak", "w").write(src)

    src, n_dark = patch_block(src, "pierre_dark_default", DARK_MAP, syntax)
    src, n_light = patch_block(src, "pierre_light_default", LIGHT_MAP, syntax)

    if n_dark + n_light == 0:
        print("ERROR: no hex values matched — themes may have moved or already patched")
        return 1

    open(MAIN_JS, "w").write(src)
    print(f"OK: rewrote {n_dark} hex values in pierre_dark_default")
    print(f"    rewrote {n_light} hex values in pierre_light_default")
    print(f"    backup at {MAIN_JS}.bak")
    print("restart hunk: pkill -f hunk; hunkr")
    return 0


if __name__ == "__main__":
    sys.exit(main())
