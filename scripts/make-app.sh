#!/bin/bash
# Legt "Minecraft Bedrock.app" in ~/Applications an, damit das Spiel über
# Spotlight, Raycast, Launchpad oder das Dock startet. Die App ruft nur
# bedrock.sh aus diesem Repo auf; nach einem Verschieben des Repos neu ausführen.
#
#   scripts/make-app.sh [Zielordner]    (Default ~/Applications)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$HOME/Applications}"
APP="$DEST/Minecraft Bedrock.app"
GAME="${BEDROCK_GAME:-$HOME/Downloads/minecraft-bedrock}"
LOGDIR="${BEDROCK_HOME:-$HOME/Games/bedrock-mac}/logs"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat >"$APP/Contents/MacOS/launch" <<EOF
#!/bin/bash
# Von scripts/make-app.sh erzeugt. Fehler landen in $LOGDIR/app.log und als Dialog.
mkdir -p "$LOGDIR"
if ! "$REPO/bedrock.sh" >"$LOGDIR/app.log" 2>&1; then
    msg="\$(grep -m1 '^Fehler:' "$LOGDIR/app.log" || tail -n 3 "$LOGDIR/app.log")"
    /usr/bin/osascript - "\$msg" >/dev/null <<'AS'
on run argv
    display alert "Minecraft Bedrock" message (item 1 of argv)
end run
AS
fi
EOF
chmod +x "$APP/Contents/MacOS/launch"

cat >"$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Minecraft Bedrock</string>
    <key>CFBundleDisplayName</key><string>Minecraft Bedrock</string>
    <key>CFBundleIdentifier</key><string>io.github.jonathanglasmeyer.bedrock-mac</string>
    <key>CFBundleExecutable</key><string>launch</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
</dict>
</plist>
EOF

# Icon aus dem größten Logo im Windows-Export bauen, falls vorhanden.
LOGO="" ; BEST=0
while IFS= read -r -d '' f; do
    size="$(stat -f%z "$f")"
    (( size > BEST )) && { BEST=$size; LOGO="$f"; }
done < <(find "$GAME" -maxdepth 3 -iname '*logo*.png' -print0 2>/dev/null)
if [[ -n "$LOGO" ]]; then
    SET="$(mktemp -d)/AppIcon.iconset"
    mkdir -p "$SET"
    for s in 16 32 128 256 512; do
        sips -z $s $s "$LOGO" --out "$SET/icon_${s}x${s}.png" >/dev/null
        sips -z $((s*2)) $((s*2)) "$LOGO" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$SET" -o "$APP/Contents/Resources/AppIcon.icns" || true
    rm -rf "$(dirname "$SET")"
fi

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
touch "$APP"
echo "==> $APP angelegt (Icon: ${LOGO:-keins gefunden})"
