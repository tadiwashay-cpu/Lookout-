#!/usr/bin/env bash
# Install a Godot add-on from GitHub into this project in one step.
#
#   tools/add_addon.sh <owner/repo> [addon_folder] [--ref <branch|tag>] [--no-enable]
#
# Example: tools/add_addon.sh godot-extended-libraries/godot-debug-menu debug_menu
#
# What it does:
#  1. clones the repo (shallow) into a temp folder
#  2. copies addons/<addon_folder> (or every folder under addons/) into ./addons/
#  3. enables any plugin.cfg it copied in project.godot [editor_plugins]
#  4. records name, source, commit and licence in addons/ADDONS.md
# Only for add-ons written in GDScript. GDExtension add-ons (Terrain3D,
# LimboAI) need prebuilt Android binaries from their Releases page instead.
set -euo pipefail

usage() { sed -n '2,13p' "$0"; exit 1; }
[ $# -ge 1 ] || usage
REPO="$1"; shift
FOLDER=""; REF=""; ENABLE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --no-enable) ENABLE=0; shift ;;
    -*) usage ;;
    *) FOLDER="$1"; shift ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Cloning https://github.com/$REPO ..."
if [ -n "$REF" ]; then
  git clone -q --depth 1 --branch "$REF" "https://github.com/$REPO.git" "$TMP/src"
else
  git clone -q --depth 1 "https://github.com/$REPO.git" "$TMP/src"
fi
COMMIT="$(git -C "$TMP/src" rev-parse --short HEAD)"

[ -d "$TMP/src/addons" ] || { echo "No addons/ folder in $REPO"; exit 1; }
if [ -n "$FOLDER" ]; then
  [ -d "$TMP/src/addons/$FOLDER" ] || { echo "addons/$FOLDER not found. Available:"; ls "$TMP/src/addons"; exit 1; }
  FOLDERS="$FOLDER"
else
  FOLDERS="$(ls "$TMP/src/addons")"
fi

if grep -rqs --include='*.gdextension' . "$TMP/src/addons"; then
  echo "WARNING: this add-on uses GDExtension (native code). Make sure Android binaries are included."
fi

LICENSE_NAME="see repo"
for f in LICENSE LICENSE.md LICENSE.txt; do
  if [ -f "$TMP/src/$f" ]; then LICENSE_NAME="$(head -1 "$TMP/src/$f" | sed 's/^#* *//')"; break; fi
done

mkdir -p "$ROOT/addons"
[ -f "$ROOT/addons/ADDONS.md" ] || printf '# Installed add-ons\n\n| Add-on | Source | Commit | Licence |\n|---|---|---|---|\n' > "$ROOT/addons/ADDONS.md"

for name in $FOLDERS; do
  rm -rf "$ROOT/addons/$name"
  cp -r "$TMP/src/addons/$name" "$ROOT/addons/$name"
  for lic in LICENSE LICENSE.md; do
    [ -f "$TMP/src/$lic" ] && [ ! -f "$ROOT/addons/$name/$lic" ] && cp "$TMP/src/$lic" "$ROOT/addons/$name/$lic"
  done
  grep -v "^| $name |" "$ROOT/addons/ADDONS.md" > "$TMP/list" || true
  cp "$TMP/list" "$ROOT/addons/ADDONS.md"
  echo "| $name | github.com/$REPO | $COMMIT | $LICENSE_NAME |" >> "$ROOT/addons/ADDONS.md"
  echo "Installed addons/$name ($COMMIT)"
  if [ $ENABLE -eq 1 ] && [ -f "$ROOT/addons/$name/plugin.cfg" ]; then
    python3 - "$ROOT/project.godot" "res://addons/$name/plugin.cfg" <<'PY'
import re, sys
path, cfg = sys.argv[1], sys.argv[2]
text = open(path).read()
m = re.search(r'^\[editor_plugins\]\s*\n\s*enabled=PackedStringArray\((.*?)\)', text, re.M | re.S)
if m:
    items = re.findall(r'"([^"]+)"', m.group(1))
    if cfg not in items:
        items.append(cfg)
    new = 'enabled=PackedStringArray(' + ', '.join('"%s"' % i for i in items) + ')'
    text = text[:m.start()] + '[editor_plugins]\n\n' + new + text[m.end():]
else:
    text = text.rstrip('\n') + '\n\n[editor_plugins]\n\nenabled=PackedStringArray("%s")\n' % cfg
open(path, 'w').write(text)
PY
    echo "Enabled plugin: res://addons/$name/plugin.cfg"
  fi
done
echo "Done. Review addons/ADDONS.md, then wire it into the game and commit."
