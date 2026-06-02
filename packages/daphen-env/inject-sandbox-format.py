"""Insert a minimal top-level starship format block before the first
[section] header. The template's existing format is inside
[palettes.custom] (TOML scoping), so starship silently ignores it. Our
injected one takes effect because it's at root scope.
"""
import re
import sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

new_format = '''format = """
[](fg:prompt)\\
[   ](bg:prompt fg:fg_muted)\\
$directory\\
[](fg:prompt) \\
$character"""

'''

content = re.sub(r'^(\[)', new_format + r'\1', content, count=1, flags=re.MULTILINE)

with open(path, 'w') as f:
    f.write(content)
