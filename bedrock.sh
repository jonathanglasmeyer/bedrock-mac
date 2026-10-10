#!/bin/bash
# Startet Minecraft Bedrock (Windows/GDK) unter WineGDK + DXMT auf dem Mac.
#
#   ./bedrock.sh                 Prefix bei Bedarf anlegen und Spiel starten
#   ./bedrock.sh --setup-only    nur Prefix anlegen
#   ./bedrock.sh --reset         Prefix dieser Version löschen (Welten liegen in $BEDROCK_HOME/data und bleiben)
#
# Pfade per Umgebung überschreibbar:
#   BEDROCK_RUNTIME  entpacktes Runtime-Tarball  (Default ~/Games/bedrock-mac/runtime)
#   BEDROCK_GAME     exportierte Spieldateien    (Default ~/Games/bedrock-mac/game, sonst ~/Downloads/minecraft-bedrock)
#   BEDROCK_HOME     Prefixe, Welten (data/), Shader-Cache, Logs (Default ~/Games/bedrock-mac)
#                    plus xgameruntime.dll.threading (native x64-xgameruntime.dll von Microsoft)
#   BEDROCK_GRAPHICS dxmt (Default, D3D11) oder d3dmetal (D3D12 über Apples D3DMetal, für
#                    Vibrant Visuals); alternativ dauerhaft in $BEDROCK_HOME/graphics
#   WINEDEBUG        Wine-Logging (Default -all; zum Debuggen z. B. +loaddll,+module)
set -euo pipefail

BEDROCK_HOME="${BEDROCK_HOME:-$HOME/Games/bedrock-mac}"
RUNTIME="${BEDROCK_RUNTIME:-$BEDROCK_HOME/runtime}"
# Apps aus dem Finder dürfen ~/Downloads nicht lesen (TCC), daher liegt der
# Export bevorzugt in $BEDROCK_HOME/game.
if [[ -z "${BEDROCK_GAME:-}" && -d "$BEDROCK_HOME/game" ]]; then
    GAME="$BEDROCK_HOME/game"
else
    GAME="${BEDROCK_GAME:-$HOME/Downloads/minecraft-bedrock}"
fi
MODE="${1:-run}"

die() { echo "Fehler: $*" >&2; exit 1; }
say() { echo "==> $*"; }

# --- Voraussetzungen ---------------------------------------------------------
[[ "$(uname -s)" == Darwin ]] || die "nur für macOS"
if [[ "$(uname -m)" == arm64 ]] && ! arch -x86_64 /usr/bin/true 2>/dev/null; then
    die "Rosetta fehlt. Installieren mit: softwareupdate --install-rosetta --agree-to-license"
fi
WINE="$RUNTIME/bin/wine"
[[ -x "$WINE" ]] || die "keine Runtime unter $RUNTIME (Artifact aus dem build-runtime-Workflow dort entpacken)"
[[ -f "$GAME/Minecraft.Windows.exe" ]] || die "keine Spieldateien unter $GAME (windows/export-minecraft.ps1 ausführen)"
[[ -f "$GAME/AppxManifest.xml" && -f "$GAME/MicrosoftGame.Config" ]] || \
    die "AppxManifest.xml oder MicrosoftGame.Config fehlt in $GAME, Export unvollständig"
[[ -r "$GAME/Minecraft.Windows.exe" ]] && head -c 2 "$GAME/Minecraft.Windows.exe" >/dev/null 2>&1 || \
    die "kein Lesezugriff auf $GAME (als App gestartet? Export nach ~/Games/bedrock-mac/game verschieben)"
if [[ "$(head -c 2 "$GAME/Minecraft.Windows.exe")" != "MZ" ]]; then
    die "Minecraft.Windows.exe ist noch verschlüsselt, Export erneut ausführen"
fi

VERSION="$(sed -n 's/^version=//p' "$GAME/BEDROCK-MAC-EXPORT.txt" 2>/dev/null | tr -d '\r' || true)"
VERSION="${VERSION:-unknown}"
PREFIX="$BEDROCK_HOME/prefix-$VERSION"
LOGDIR="$BEDROCK_HOME/logs"
mkdir -p "$BEDROCK_HOME" "$LOGDIR" "$BEDROCK_HOME/shader-cache"

if [[ "$MODE" == --reset ]]; then
    say "lösche $PREFIX"
    rm -rf "$PREFIX"
    exit 0
fi

# Aus dem Browser geladene Runtime ist in Quarantäne; Gatekeeper würde jede Datei einzeln blocken.
xattr -dr com.apple.quarantine "$RUNTIME" 2>/dev/null || true

# --- Grafik-Backend ----------------------------------------------------------
# DXMT kann nur D3D11, Vibrant Visuals braucht D3D12. D3DMetal aus Apples Game
# Porting Toolkit kann beides, darf aber nicht mitgeliefert werden: Den Ordner
# redist/lib aus dem Toolkit nach $BEDROCK_HOME/d3dmetal kopieren (enthält
# external/ und wine/). Daraus entsteht eine eigene Runtime-Kopie (APFS-Klon),
# in der D3DMetals d3d11/d3d12/dxgi die von DXMT und vkd3d ersetzen. Die
# winemac-Seite dafür bringt patches/winegdk/0102 mit.
GRAPHICS="${BEDROCK_GRAPHICS:-$(tr -d '[:space:]' <"$BEDROCK_HOME/graphics" 2>/dev/null || true)}"
GRAPHICS="${GRAPHICS:-dxmt}"
case "$GRAPHICS" in
dxmt) ;;
d3dmetal)
    GPTK="${BEDROCK_D3DMETAL:-$BEDROCK_HOME/d3dmetal}"
    [[ -f "$GPTK/wine/x86_64-windows/d3d12.dll" && -d "$GPTK/external" ]] || \
        die "kein D3DMetal unter $GPTK (redist/lib aus Apples Game Porting Toolkit dorthin kopieren, siehe README)"
    xattr -dr com.apple.quarantine "$GPTK" 2>/dev/null || true
    OVERLAY="$BEDROCK_HOME/runtime-d3dmetal"
    STAMP="$(cat "$RUNTIME/share/bedrock-mac/BUILDINFO" 2>/dev/null; cd "$GPTK" && find . -type f -exec stat -f '%N %z %m' {} + | sort)"
    if [[ "$(cat "$OVERLAY/.bedrock-d3dmetal" 2>/dev/null)" != "$STAMP" ]]; then
        say "baue Runtime mit D3DMetal: $OVERLAY"
        rm -rf "$OVERLAY"
        mkdir -p "$OVERLAY"
        cp -Rc "$RUNTIME/." "$OVERLAY/" 2>/dev/null || cp -R "$RUNTIME/." "$OVERLAY/"
        cp -R "$GPTK/wine/." "$OVERLAY/lib/wine/"
        cp -R "$GPTK/external" "$OVERLAY/lib/"
        printf '%s\n' "$STAMP" >"$OVERLAY/.bedrock-d3dmetal"
    fi
    RUNTIME="$OVERLAY"
    WINE="$RUNTIME/bin/wine"
    ;;
*) die "unbekanntes Grafik-Backend '$GRAPHICS' (dxmt oder d3dmetal)" ;;
esac

# --- Umgebung ----------------------------------------------------------------
export WINEPREFIX="$PREFIX"
export WINEDEBUG="${WINEDEBUG:--all}"
# Wine lädt gnutls/freetype per dlopen über den Namen.
export DYLD_FALLBACK_LIBRARY_PATH="$RUNTIME/lib:/usr/lib"
if [[ "$GRAPHICS" == d3dmetal ]]; then
    # D3DMetal.framework und libd3dshared.dylib liegen in lib/external.
    export DYLD_FALLBACK_LIBRARY_PATH="$RUNTIME/lib/external:$DYLD_FALLBACK_LIBRARY_PATH"
    export DYLD_FALLBACK_FRAMEWORK_PATH="$RUNTIME/lib/external${DYLD_FALLBACK_FRAMEWORK_PATH:+:$DYLD_FALLBACK_FRAMEWORK_PATH}"
    # Auch hier heißt "builtin" die Dateien aus der Runtime-Kopie, also D3DMetal.
    OVERRIDES="d3d11,d3d12,dxgi,d3d10core=b"
else
    export DXMT_SHADER_CACHE_PATH="$BEDROCK_HOME/shader-cache"
    # DXMT ersetzt d3d11/dxgi im Runtime-Verzeichnis, "builtin" heißt hier also DXMT.
    OVERRIDES="d3d11,dxgi,d3d10core,winemetal=b"
fi
# Kein Wine-Mono/Gecko: Minecraft braucht weder .NET noch den HTML-Renderer, und
# ohne das fragt Wine bei jedem Prefix-Update nach dem Download.
export WINEDLLOVERRIDES="mscoree,mshtml=${WINEDLLOVERRIDES:+;$WINEDLLOVERRIDES}"

C_GAME="$PREFIX/drive_c/Program Files/Minecraft Launcher"
C_GAMEINPUT="$PREFIX/drive_c/Program Files/Microsoft GameInput"

# --- Prefix einrichten -------------------------------------------------------
if [[ ! -f "$PREFIX/system.reg" ]]; then
    say "lege Prefix an: $PREFIX"
    "$WINE" wineboot -i >"$LOGDIR/wineboot.log" 2>&1
    "$RUNTIME/bin/wineserver" -w
fi

# Welten, Einstellungen und Skins liegen außerhalb der versionsgebundenen
# Prefixe, damit sie ein Spiel-Update überleben.
DATA="$BEDROCK_HOME/data"
C_DATA="$PREFIX/drive_c/users/$USER/AppData/Roaming/Minecraft Bedrock"
mkdir -p "$DATA" "$(dirname "$C_DATA")"
if [[ -d "$C_DATA" && ! -L "$C_DATA" ]]; then
    cp -Rn "$C_DATA/." "$DATA/" 2>/dev/null || true
    rm -rf "$C_DATA"
fi
ln -sfn "$DATA" "$C_DATA"

if [[ ! -f "$C_GAME/Minecraft.Windows.exe" ]] || \
   ! cmp -s "$GAME/BEDROCK-MAC-EXPORT.txt" "$C_GAME/BEDROCK-MAC-EXPORT.txt"; then
    say "kopiere Spieldateien in den Prefix (APFS-Klon, kostet kaum Platz)"
    rm -rf "$C_GAME"
    mkdir -p "$(dirname "$C_GAME")"
    cp -Rc "$GAME" "$C_GAME" 2>/dev/null || cp -R "$GAME" "$C_GAME"
    rm -rf "$C_GAME/_gameinput"
fi

# Neuere Builds starten über den Windows-App-SDK-Bootstrapper, der unter Wine
# mangels MSIX-Paketverwaltung scheitert. Der Stub meldet einfach Erfolg.
STUB="$(cd "$(dirname "$0")" && pwd)/stubs/Microsoft.WindowsAppRuntime.Bootstrap.dll"
if [[ -f "$C_GAME/Microsoft.WindowsAppRuntime.Bootstrap.dll" ]] && \
   ! cmp -s "$STUB" "$C_GAME/Microsoft.WindowsAppRuntime.Bootstrap.dll"; then
    say "ersetze den Windows-App-SDK-Bootstrapper durch einen Stub"
    cp "$STUB" "$C_GAME/Microsoft.WindowsAppRuntime.Bootstrap.dll"
fi

# XThreading läuft nur mit Microsofts nativer x64-xgameruntime.dll stabil, sonst
# stürzt das Spiel in einem Worker-Thread ab. Quelle: x64-Paket "Gaming Services"
# (xgameruntime.dll im GamingServicesTcui-Package_*_x64.appx), siehe README.
THREADING="$BEDROCK_HOME/xgameruntime.dll.threading"
C_THREADING="$PREFIX/drive_c/windows/system32/xgameruntime.dll.threading"
if [[ -f "$THREADING" ]]; then
    cmp -s "$THREADING" "$C_THREADING" || cp "$THREADING" "$C_THREADING"
else
    say "Warnung: $THREADING fehlt, das Spiel stürzt vermutlich beim Laden ab"
fi

if [[ -d "$GAME/_gameinput/x64" ]]; then
    # Die Maus geht nur mit Microsofts Redist; WineGDKs eingebautes gameinput.dll
    # liefert unter Wine keine Maustasten. Das Spiel lädt die Redist nur, wenn
    # RedistDir ohne abschließenden Backslash gesetzt ist und sie in system32 liegt.
    if [[ ! -f "$PREFIX/drive_c/windows/system32/GameInputRedist.dll" ]]; then
        say "richte GameInput aus dem Windows-Export ein"
        mkdir -p "$C_GAMEINPUT"
        cp -R "$GAME/_gameinput/." "$C_GAMEINPUT/"
        rm -f "$C_GAMEINPUT/gameinput.reg"
        cp "$C_GAMEINPUT/x64/GameInputRedist.dll" "$PREFIX/drive_c/windows/system32/"
        if [[ -f "$GAME/_gameinput/gameinput.reg" ]]; then
            "$WINE" regedit /S "Z:$(echo "$GAME/_gameinput/gameinput.reg" | tr / '\\')" >>"$LOGDIR/wineboot.log" 2>&1
        fi
        for KEY in 'HKLM\SOFTWARE\Microsoft\GameInput' 'HKLM\SOFTWARE\Wow6432Node\Microsoft\GameInput'; do
            "$WINE" reg add "$KEY" /v RedistDir /t REG_SZ \
                /d 'C:\Program Files\Microsoft GameInput\x64' /f >>"$LOGDIR/wineboot.log" 2>&1
        done
        SVC='HKLM\SYSTEM\CurrentControlSet\Services\GameInputRedistService'
        "$WINE" reg add "$SVC" /v ImagePath /t REG_EXPAND_SZ \
            /d 'C:\Program Files\Microsoft GameInput\x64\GameInputRedistService.exe' /f >>"$LOGDIR/wineboot.log" 2>&1
        "$WINE" reg add "$SVC" /v Type /t REG_DWORD /d 16 /f >>"$LOGDIR/wineboot.log" 2>&1
        "$WINE" reg add "$SVC" /v Start /t REG_DWORD /d 3 /f >>"$LOGDIR/wineboot.log" 2>&1
        "$RUNTIME/bin/wineserver" -w
    fi
else
    say "keine GameInput-Redist im Export, nutze die eingebaute von WineGDK"
    OVERRIDES="$OVERRIDES;gameinput,GameInputRedist=b"
fi

# Xbox-Login: WineGDKs XUser holt sich mit dem Refresh-Token aus xbox-login.py
# selbst die Xbox-Live-Tokens. ConsoleMode=8 schaltet Minecraft auf den
# XSAPI-Pfad, und Azure lehnt Wines TLS-1.3-Handshake ab, daher TLS 1.2.
# Werte wie in BedrockOnLinux (bol/auth.py). Nur bei Änderung importieren.
TOKEN_FILE="$BEDROCK_HOME/msa-refresh-token"
if [[ -s "$TOKEN_FILE" ]]; then
    TOKEN_LINE="\"RefreshToken\"=\"$(tr -d '\r\n"\\' <"$TOKEN_FILE")\""
else
    TOKEN_LINE='"RefreshToken"=-'
fi
XBOX_REG="$(cat <<EOF
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows NT\\CurrentVersion\\OEM]
"ConsoleMode"=dword:00000008

[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings\\WinHttp]
"DefaultSecureProtocols"=dword:00000a00

[HKEY_LOCAL_MACHINE\\Software\\Microsoft\\SchannelTLS\\Protocols\\TLS 1.3\\Client]
"DisabledByDefault"=dword:00000001

[HKEY_LOCAL_MACHINE\\Software\\Wine\\WineGDK]
$TOKEN_LINE
EOF
)"
if [[ "$(cat "$PREFIX/.bedrock-xbox.reg" 2>/dev/null)" != "$XBOX_REG" ]]; then
    say "trage Xbox-Login-Einstellungen in den Prefix ein"
    printf '%s\n' "$XBOX_REG" >"$PREFIX/.bedrock-xbox.reg"
    chmod 600 "$PREFIX/.bedrock-xbox.reg"
    "$WINE" regedit /S "Z:$(echo "$PREFIX/.bedrock-xbox.reg" | tr / '\\')" >>"$LOGDIR/wineboot.log" 2>&1
    "$RUNTIME/bin/wineserver" -w
fi
[[ -s "$TOKEN_FILE" ]] || say "nicht bei Xbox angemeldet, dafür einmal ./xbox-login.py ausführen"

# Ist in macOS eine Eingabemethode statt eines reinen Layouts aktiv, meldet
# Wine sonst eine IME-Tastatur und das Spiel sieht jede Taste als VK_PROCESSKEY.
export WINEMAC_NO_IME_HKL=1
# Tasten nach physischer Position (US-Belegung) statt nach Mac-Layout, damit
# WASD auch mit Workman, Dvorak oder Colemak an der gewohnten Stelle liegt.
# Getippter Text (Chat, Weltnamen) folgt weiter dem Mac-Layout.
# BEDROCK_LAYOUT_KEYS=1 schaltet das ab.
[[ -n "${BEDROCK_LAYOUT_KEYS:-}" ]] || export WINEMAC_PHYSICAL_KEYS=1

[[ "$MODE" == --setup-only ]] && { say "Prefix fertig"; exit 0; }

# --- Start -------------------------------------------------------------------
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+$WINEDLLOVERRIDES;}$OVERRIDES"
LOG="$LOGDIR/minecraft-$(date +%Y%m%d-%H%M%S).log"
say "starte Minecraft $VERSION mit $GRAPHICS (Log: $LOG)"
cd "$C_GAME"

# Wine übersetzt Tasten über das aktive macOS-Layout, Spiele wollen aber Positionen.
# Mit alternativem Layout (Workman, Dvorak …) die ID eines QWERTY-Layouts in
# $BEDROCK_HOME/input-source ablegen (z. B. com.apple.keylayout.US); dann wird es
# für die Spieldauer aktiviert und danach das vorherige wiederhergestellt.
INPUT_SOURCE="${BEDROCK_INPUT_SOURCE:-$(cat "$BEDROCK_HOME/input-source" 2>/dev/null || true)}"
if [[ -n "$INPUT_SOURCE" ]]; then
    ISW="$BEDROCK_HOME/bin/inputsource"
    ISW_SRC="$(cd "$(dirname "$0")" && pwd)/scripts/inputsource.swift"
    if [[ ! -x "$ISW" || "$ISW_SRC" -nt "$ISW" ]]; then
        mkdir -p "$(dirname "$ISW")"
        xcrun swiftc -O "$ISW_SRC" -o "$ISW" >>"$LOGDIR/wineboot.log" 2>&1 || ISW=""
    fi
    if [[ -n "$ISW" ]] && PREV_SOURCE="$("$ISW")" && "$ISW" "$INPUT_SOURCE"; then
        say "Tastaturlayout für die Spieldauer: $INPUT_SOURCE (danach wieder $PREV_SOURCE)"
        trap '"$ISW" "$PREV_SOURCE"' EXIT
        "$WINE" 'C:\Program Files\Minecraft Launcher\Minecraft.Windows.exe' >"$LOG" 2>&1
        exit $?
    fi
    say "Warnung: konnte das Tastaturlayout nicht auf $INPUT_SOURCE umstellen"
fi
exec "$WINE" 'C:\Program Files\Minecraft Launcher\Minecraft.Windows.exe' >"$LOG" 2>&1
