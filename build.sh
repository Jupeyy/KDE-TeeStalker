#!/usr/bin/env bash
set -euo pipefail

# --- config -------------------------------------------------------------

CONFIG_FILE="$HOME/.local/share/ddnet/settings_ddnet.cfg"

# Where your plasmoid package is (metadata.json, contents/, etc.)
SRC_PKG_DIR="$PWD/package"

# Where to build and install from
BUILD_DIR="$PWD/build"
BUILD_PKG_DIR="$BUILD_DIR/package"
MAIN_QML="$BUILD_PKG_DIR/contents/ui/main.qml"

# kpackagetool; you wrote kpackagetool6 – keep that if it's correct on your system
KPKGTOOL="kpackagetool6"
# KPKGTOOL="kpackagetool6"  # typical name on many systems

# --- clean + copy package -----------------------------------------------

echo "Cleaning build dir: $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "Copying package from $SRC_PKG_DIR -> $BUILD_PKG_DIR"
cp -a "$SRC_PKG_DIR" "$BUILD_PKG_DIR"

# --- parse friends from settings_ddnet.cfg ------------------------------

friends=()

if [[ -f "$CONFIG_FILE" ]]; then
    echo "Reading friends from: $CONFIG_FILE"
    while IFS= read -r line; do
        [[ $line == add_friend* ]] || continue

        # Match: add_friend "Name" "Clan"
        if [[ $line =~ add_friend[[:space:]]+\"([^\"]*)\" ]]; then
            name=${BASH_REMATCH[1]}
            [[ -n $name ]] && friends+=("$name")
        fi
    done < "$CONFIG_FILE"
else
    echo "WARNING: Config file not found: $CONFIG_FILE" >&2
fi

echo "Found ${#friends[@]} friend(s)"

# --- build QML array literal --------------------------------------------

# Create: [ "A", "B", "C" ]
qml_array="[ "
for name in "${friends[@]}"; do
    esc=${name//\\/\\\\}   # escape backslashes
    esc=${esc//\"/\\\"}    # escape double quotes
    qml_array+="\"$esc\", "
done
qml_array="${qml_array%, } ]"   # remove trailing comma+space

echo "Generating trackedNames: $qml_array"

# --- patch main.qml: replace property var trackedNames: ... -------------

if [[ ! -f "$MAIN_QML" ]]; then
    echo "ERROR: main.qml not found at $MAIN_QML" >&2
    exit 1
fi

python3 - "$MAIN_QML" "$qml_array" << 'PY'
import sys, re

path, array = sys.argv[1], sys.argv[2]

with open(path, encoding="utf-8") as f:
    text = f.read()

# Replace the first occurrence of: property var trackedNames: ...
pattern = r'property\s+var\s+trackedNames\s*:[^\n]*'
replacement = 'property var trackedNames: ' + array

new, count = re.subn(pattern, replacement, text, count=1)

if count == 0:
    sys.stderr.write(
        "ERROR: trackedNames property not found in %s\n" % path
    )
    sys.exit(1)

with open(path, "w", encoding="utf-8") as f:
    f.write(new)
PY

echo "Patched trackedNames in $MAIN_QML"

# --- install plasmoid ---------------------------------------------------

echo "Installing plasmoid from $BUILD_PKG_DIR"
PKG_ID="org.ddnet.teestalker"
PKG_DIR="$BUILD_PKG_DIR"
CMD="$KPKGTOOL"   # e.g., kpackagetool6 or kpackagetool5

# Check if installed
if "$CMD" --type Plasma/Applet --list | grep -q "$PKG_ID"; then
    echo "Package $PKG_ID is already installed → upgrading"
    "$CMD" --type Plasma/Applet --upgrade "$PKG_DIR"
else
    echo "Package $PKG_ID is not installed → installing"
    "$CMD" --type Plasma/Applet --install "$PKG_DIR"
fi

echo "Done."
