# bedrock-mac

Offener Weg, Minecraft Bedrock (Windows/GDK-Version) auf Apple-Silicon-Macs zu spielen, ohne Android-Emulator und ohne Closed-Source-Launcher.

Bausteine, alle Open Source:

- [WineGDK](https://github.com/Weather-OS/WineGDK): Wine 11 mit GDK-Komponenten (xgameruntime, XUser, AppModel, GameInput) und der Xodus-Login-Brücke.
- [DXMT](https://github.com/3Shain/dxmt): Direct3D 11 nach Metal.
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
2. Spieldateien per Export-Skript nach `~/Downloads/minecraft-bedrock` holen (siehe oben).
3. Microsofts native x64-`xgameruntime.dll` als `~/Games/bedrock-mac/xgameruntime.dll.threading` ablegen. WineGDK nutzt sie für XThreading, ohne sie stürzt das Spiel beim Laden ab. Auf einem x64-Windows liegt sie unter `C:\Windows\System32\xgameruntime.dll`. Auf Windows on ARM gibt es dort nur ARM64, dann aus dem x64-Paket "Gaming Services" (`Microsoft.GamingServices_8wekyb3d8bbwe`, z. B. über store.rg-adguard.net) die Datei `GamingServicesTcui-Package_*_x64.appx` und daraus `xgameruntime.dll` entpacken.
4. `./bedrock.sh`

Logs landen unter `~/Games/bedrock-mac/logs/`. Für ausführliches Wine-Logging `WINEDEBUG=+loaddll,+module ./bedrock.sh`. Erstes Ziel ist Singleplayer und LAN ohne Xbox-Login; Vibrant Visuals und Login sind noch offen.
