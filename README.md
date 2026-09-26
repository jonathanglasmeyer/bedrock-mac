# bedrock-mac

Offener Weg, Minecraft Bedrock (Windows/GDK-Version) auf Apple-Silicon-Macs zu spielen, ohne Android-Emulator und ohne Closed-Source-Launcher.

Bausteine, alle Open Source:

- [WineGDK](https://github.com/Weather-OS/WineGDK): Wine 11 mit GDK-Komponenten (xgameruntime, XUser, AppModel, GameInput) und der Xodus-Login-Brücke.
- [DXMT](https://github.com/3Shain/dxmt): Direct3D 11 nach Metal.
- Spieldateien aus der eigenen, lizenzierten Windows-Installation (kein DRM-Bypass in diesem Repo).

## Stand

1. **Runtime-Build** (dieses Repo, `build-runtime`-Workflow): baut WineGDK auf einem gepinnten Commit für x86_64 (läuft über Rosetta), legt die offiziellen, per Build-Provenance verifizierten DXMT-Binaries dazu und bündelt die Homebrew-Bibliotheken. Ergebnis ist ein `tar.xz` als Actions-Artifact, `share/bedrock-mac/BUILDINFO` nennt die exakten Quellen.
2. Spieldateien-Export vom Windows-PC: folgt.
3. Startskript (Prefix, GameInput, Launch): folgt.
4. Xodus-Provider für Xbox-Login: folgt.

## Runtime bauen

Actions → `build-runtime` → Run workflow. Eingaben `winegdk_ref` und `dxmt_tag` sind optional.

Die Runtime lädt gnutls, freetype und Vulkan per `dlopen`; beim Start muss `DYLD_FALLBACK_LIBRARY_PATH` auf `<runtime>/lib` zeigen. Die ursprünglichen wined3d-DLLs liegen als Fallback unter `share/bedrock-mac/wined3d/`.
