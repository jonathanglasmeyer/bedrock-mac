# bedrock-mac

Offener Weg, Minecraft Bedrock (Windows/GDK-Version) auf Apple-Silicon-Macs zu spielen, ohne Android-Emulator und ohne Closed-Source-Launcher.

Bausteine, alle Open Source:

- [WineGDK](https://github.com/Weather-OS/WineGDK): Wine 11 mit GDK-Komponenten (xgameruntime, XUser, AppModel, GameInput) und der Xodus-Login-Brücke.
- [DXMT](https://github.com/3Shain/dxmt): Direct3D 11 nach Metal.
- Spieldateien aus der eigenen, lizenzierten Windows-Installation (kein DRM-Bypass in diesem Repo).

## Stand

1. **Runtime-Build** (dieses Repo, `build-runtime`-Workflow): baut WineGDK auf einem gepinnten Commit für x86_64 (läuft über Rosetta), legt die offiziellen, per Build-Provenance verifizierten DXMT-Binaries dazu und bündelt die Bibliotheken (gnutls, freetype) aus MacPorts. Gebaut wird auf einem Intel-Runner, weil Homebrew kein Intel mehr unterstützt; Wine für macOS ist ohnehin x86_64 und läuft auf Apple Silicon über Rosetta. Ergebnis ist ein `tar.xz` als Actions-Artifact, `share/bedrock-mac/BUILDINFO` nennt die exakten Quellen.
2. **Spieldateien-Export** (`windows/export-minecraft.ps1`): kopiert die per Xbox-App installierte Version im Paketkontext, sodass Windows selbst die Klartextfassung liefert, prüft die exe (x64) und legt alles in einem Ordner ab. Funktioniert auf einem Windows-PC oder in einer Windows-11-VM in Parallels (Trial reicht, Minecraft ist dort ebenfalls die x64-Version).
3. Startskript (Prefix, GameInput, Launch): folgt.
4. Xodus-Provider für Xbox-Login: folgt.

## Runtime bauen

Actions → `build-runtime` → Run workflow. Eingaben `winegdk_ref` und `dxmt_tag` sind optional.

Die Runtime lädt gnutls und freetype per `dlopen`; beim Start muss `DYLD_FALLBACK_LIBRARY_PATH` auf `<runtime>/lib` zeigen. Die ursprünglichen wined3d-DLLs liegen als Fallback unter `share/bedrock-mac/wined3d/`.

## Spieldateien exportieren

Auf Windows (echter PC oder Parallels-VM): Minecraft über die Xbox-App installieren und einmal starten. Dann PowerShell als Administrator:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\export-minecraft.ps1                       # Ziel: \\Mac\Home\Downloads\minecraft-bedrock (Parallels-Freigabe)
.\export-minecraft.ps1 -Destination D:\mc   # anderes Ziel
```

Das Skript bricht ab, wenn die exe noch verschlüsselt oder keine x64-Datei ist.
