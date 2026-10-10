# bedrock-mac

Offener Weg, Minecraft Bedrock (Windows/GDK-Version) auf Apple-Silicon-Macs zu spielen, ohne Android-Emulator und ohne Closed-Source-Launcher.

Bausteine, alle Open Source:

- [WineGDK](https://github.com/Weather-OS/WineGDK): Wine 11 mit GDK-Komponenten (xgameruntime, XUser, AppModel, GameInput) und der Xodus-Login-Brücke.
- [DXMT](https://github.com/3Shain/dxmt): Direct3D 11 nach Metal.
- Optional D3DMetal aus Apples [Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/) für Direct3D 12 (nicht Open Source, wird nicht mitgeliefert).
- Spieldateien aus der eigenen, lizenzierten Windows-Installation (kein DRM-Bypass in diesem Repo).

## Stand

1. **Runtime-Build** (dieses Repo, `build-runtime`-Workflow): baut WineGDK auf einem gepinnten Commit für x86_64 (läuft über Rosetta), legt die offiziellen, per Build-Provenance verifizierten DXMT-Binaries dazu und bündelt die Bibliotheken (gnutls, freetype) aus MacPorts. Gebaut wird auf einem Intel-Runner, weil Homebrew kein Intel mehr unterstützt; Wine für macOS ist ohnehin x86_64 und läuft auf Apple Silicon über Rosetta. Ergebnis ist ein `tar.xz` als Actions-Artifact, `share/bedrock-mac/BUILDINFO` nennt die exakten Quellen.
2. **Spieldateien-Export** (`windows/export-minecraft.ps1`): kopiert die per Xbox-App installierte Version im Paketkontext, sodass Windows selbst die Klartextfassung liefert, prüft die exe (x64) und legt alles in einem Ordner ab. Funktioniert auf einem Windows-PC oder in einer Windows-11-VM in Parallels (Trial reicht, Minecraft ist dort ebenfalls die x64-Version).
3. **Startskript** (`bedrock.sh`): legt pro Spielversion einen Prefix an, klont die Spieldateien hinein, richtet GameInput aus dem Windows-Export ein und startet das Spiel mit DXMT. Noch ungetestet auf echter Hardware.
4. Xodus-Provider für Xbox-Login: folgt.

## Runtime bauen

Actions → `build-runtime` → Run workflow. Eingaben `winegdk_ref` und `dxmt_tag` sind optional.

Die Runtime lädt gnutls und freetype per `dlopen`; beim Start muss `DYLD_FALLBACK_LIBRARY_PATH` auf `<runtime>/lib` zeigen. Die ursprünglichen wined3d-DLLs liegen als Fallback unter `share/bedrock-mac/wined3d/`.

## Spieldateien exportieren

Auf Windows (echter PC oder Parallels-VM): Minecraft über die Xbox-App installieren und einmal starten. Dann eine normale PowerShell (keine Adminrechte nötig):

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\export-minecraft.ps1                       # Ziel: \\Mac\Home\Downloads\minecraft-bedrock (Parallels-Freigabe)
.\export-minecraft.ps1 -Destination D:\mc   # anderes Ziel
```

Das Skript bricht ab, wenn die exe noch verschlüsselt oder keine x64-Datei ist.

## Spielen

1. Artifact aus dem letzten grünen `build-runtime`-Lauf laden und entpacken:
   ```sh
   mkdir -p ~/Games/bedrock-mac/runtime
   tar -xJf bedrock-mac-runtime-*.tar.xz -C ~/Games/bedrock-mac/runtime
   ```
2. Spieldateien per Export-Skript nach `~/Downloads/minecraft-bedrock` holen (siehe oben). `scripts/make-app.sh` verschiebt sie nach `~/Games/bedrock-mac/game` und lässt einen Symlink zurück, weil aus dem Finder gestartete Apps `~/Downloads` nicht lesen dürfen.
3. Microsofts native x64-`xgameruntime.dll` als `~/Games/bedrock-mac/xgameruntime.dll.threading` ablegen. WineGDK nutzt sie für XThreading, ohne sie stürzt das Spiel beim Laden ab. Auf einem x64-Windows liegt sie unter `C:\Windows\System32\xgameruntime.dll`. Auf Windows on ARM gibt es dort nur ARM64, dann aus dem x64-Paket "Gaming Services" (`Microsoft.GamingServices_8wekyb3d8bbwe`, z. B. über store.rg-adguard.net) die Datei `GamingServicesTcui-Package_*_x64.appx` und daraus `xgameruntime.dll` entpacken.
4. Optional für Xbox-Login: einmal `./xbox-login.py`, Code im Browser eingeben. Der Refresh-Token landet in `~/Games/bedrock-mac/msa-refresh-token`, `bedrock.sh` trägt ihn in den Prefix ein. `./xbox-login.py --logout` meldet wieder ab.
5. `./bedrock.sh`, oder einmal `scripts/make-app.sh` ausführen: Das legt `~/Applications/Minecraft Bedrock.app` an, die über Spotlight, Raycast oder das Dock startet (Fehler erscheinen als Dialog, Ausgabe in `logs/app.log`).

Wer in macOS ein alternatives Layout nutzt (Workman, Dvorak, Colemak), legt die ID eines QWERTY-Layouts in `~/Games/bedrock-mac/input-source` ab, z. B. `echo com.apple.keylayout.US > ~/Games/bedrock-mac/input-source`. `bedrock.sh` schaltet es für die Spieldauer ein und danach zurück, sonst liegt WASD auf den falschen Tasten.

Logs landen unter `~/Games/bedrock-mac/logs/`. Für ausführliches Wine-Logging `WINEDEBUG=+loaddll,+module ./bedrock.sh`. Singleplayer und LAN laufen; der Xbox-Login ist in Arbeit, Vibrant Visuals (DX12) siehe unten.

## Vibrant Visuals (D3DMetal, experimentell)

Vibrant Visuals setzt auf dem PC Direct3D 12 voraus ([FAQ](https://feedback.minecraft.net/hc/en-us/community/posts/35391950770317-Vibrant-Visuals-FAQ-Thread)), DXMT kann nur D3D11. Mit DXMT bietet das Spiel deshalb nur Simple und Fancy an. Apples D3DMetal übersetzt D3D11 und D3D12 nach Metal; [bedrockformac](https://github.com/goofygabe8/bedrockformac) nutzt es für dieselbe GDK-Version und bietet dort Vibrant Visuals an.

1. Game Porting Toolkit bei Apple laden (kostenloser Developer-Account): [developer.apple.com/games](https://developer.apple.com/games/game-porting-toolkit/). GPTK 3 für aktuelle macOS-Versionen, GPTK 4 (Beta) ist bisher mit macOS 27 belegt.
2. Im DMG `Evaluation environment for Windows games *.dmg` öffnen und den Ordner `redist/lib` nach `~/Games/bedrock-mac/d3dmetal` kopieren, sodass dort `external/` und `wine/` liegen:
   ```sh
   cp -R "/Volumes/Evaluation environment for Windows games 3.0/redist/lib" ~/Games/bedrock-mac/d3dmetal
   ```
3. Einmal ausprobieren mit `BEDROCK_GRAPHICS=d3dmetal ./bedrock.sh`, dauerhaft (auch für die App) mit `echo d3dmetal > ~/Games/bedrock-mac/graphics`. Zurück zu DXMT: Datei löschen.

`bedrock.sh` legt daraus `~/Games/bedrock-mac/runtime-d3dmetal` an, eine APFS-Kopie der Runtime, in der D3DMetals `d3d11`, `d3d12` und `dxgi` die DLLs von DXMT und vkd3d ersetzen. Die Kopie wird neu gebaut, wenn sich Runtime oder Toolkit ändern. Die Fensteranbindung, die D3DMetal im Mac-Treiber erwartet, steckt bereits in `0102-winemac-dxmt-support-backport.patch`. Ungetestet: ob das Spiel damit startet und Vibrant Visuals in den Videoeinstellungen erscheint. Bei Problemen hilft `WINEDEBUG=+loaddll ./bedrock.sh`, im Log muss `d3d12.dll` aus `runtime-d3dmetal` geladen werden.

## Patches

`patches/winegdk/` wird im Build auf den gepinnten WineGDK-Commit angewendet. Der Commit `75637b6` und die `bol-*`-Patches stammen aus [BedrockOnLinux](https://github.com/Wyze3306/BedrockOnLinux) (MIT, `third_party/winegdk-native5`): XUser mit echtem Xbox-Live-Login, Xbox-Kontext, Realms, XStore- und XSystem-Fixes. Nicht übernommen sind der X11-Patch und das Laden einer verschlüsselten Exe aus dem Speicher, weil wir die Spieldateien aus der eigenen Windows-Installation exportieren. `0101-winemac-optional-plain-keyboard-hkl.patch` ist von hier: Mit `WINEMAC_NO_IME_HKL=1` meldet Wines Mac-Treiber auch bei Eingabemethoden (z. B. eigenen Layouts wie Workman) eine normale Tastatur, sonst kommt jede Taste als VK_PROCESSKEY (229) im Spiel an. `0103-winemac-physical-key-vkeys.patch` ebenso: Mit `WINEMAC_PHYSICAL_KEYS=1` (setzt `bedrock.sh`, abschaltbar mit `BEDROCK_LAYOUT_KEYS=1`) bekommt das Spiel die Tasten nach physischer Position wie bei einer US-Tastatur, getippter Text folgt weiter dem Mac-Layout. `0104-winemac-client-view-follows-window-resize.patch` lässt die Metal-Zeichenfläche mit dem Fenster mitwachsen, sonst bleibt nach dem Wechsel von maximiert zu Vollbild unten ein weißer Streifen.
