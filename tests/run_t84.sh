#!/usr/bin/env bash
# t84 (sound editor) in a real Windows LiveCode through LIB_MCP's standalone (port 8767): LIB_SFX's DLL
# only loads on Windows. Needs LIB_SFX/build.bat to have run once. Silent, no window shown.
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
OUT="$("$HERE/../../LIB_MCP/tools/lcmcp" --standalone run - < "$HERE/t84_sound_edit.txt" 2>&1)"
echo "$OUT"
if echo "$OUT" | grep -q "^names: done" && ! echo "$OUT" | grep -q ": false"; then
  echo "PASS: $(echo "$OUT" | grep -c ': true') checks"
else
  echo "FAIL"; exit 1
fi
