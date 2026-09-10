#!/usr/bin/env bash
# Build all three local targets for Tetris: Linux, Web, Android.
#
# Run this ONLY with the Godot editor closed — a second Godot process on an
# open project corrupts the .godot/ caches.
#
#   bash projects/tetris/build.sh            # all three
#   bash projects/tetris/build.sh web        # just one (linux | web | android)
set -e

GODOT=~/GodotDev/learn_2d_gamedev_godot_4_0.57.0_linux/godot
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADB=~/Android/Sdk/platform-tools/adb
targets="${*:-linux web android}"

cd "$HERE"

# help images: rasterise SVG -> PNG, then let Godot import everything
[ -x assets/help_src/render.sh ] && bash assets/help_src/render.sh
"$GODOT" --headless --path . --import

for t in $targets; do
  case "$t" in
    linux)
      "$GODOT" --headless --path . --export-release "Linux" ../tetris-linux.x86_64
      chmod +x ../tetris-linux.x86_64
      ;;
    web)
      mkdir -p ../web-release-tetris
      "$GODOT" --headless --path . --export-release "Web" ../web-release-tetris/index.html
      ;;
    android)
      "$GODOT" --headless --path . --export-release "Android" ../tetris-android.apk
      if "$ADB" get-state >/dev/null 2>&1; then
        "$ADB" install -r ../tetris-android.apk
      else
        echo "  (no device connected — APK built, not installed)"
      fi
      ;;
    *) echo "unknown target: $t" ;;
  esac
done

echo
echo "done: $targets"
