# bedrock-mac

Minecraft Bedrock (Windows-GDK) auf Apple Silicon: WineGDK x86_64 unter Rosetta, Grafik über DXMT (D3D11) oder D3DMetal (D3D12, Vibrant Visuals). Überblick in `README.md`.

## Regeln

- Kommunikation und Commits auf Deutsch, du-Form, keine Em-Dashes. Keine Attribution-Trailer, nie `--no-verify`.
- D3DMetal/GPTK-Dateien nie committen, hochladen oder in Artifacts bündeln (Apple-Lizenz). `bedrock.sh` kopiert sie nur lokal in `runtime-d3dmetal`.
- Unter `~/Games/bedrock-mac` nichts löschen: `data` (Welten), `runtime*`, `prefix-*`, `game`. Runtime-Wechsel per `mv runtime runtime-old-<run-id>`, Run-ID steht in `runtime/share/bedrock-mac/BUILDINFO`.
- Remote ist privat (`jonathanglasmeyer`), Push dorthin ist ok.
- Solo-Projekt: keine PRs oder Feature-Branches, direkt auf `main` committen. Push auf `main` mit Änderungen unter `patches/**` startet den Runtime-Build.

## Build

- Runtime baut nur CI: Workflow `build-runtime` (`workflow_dispatch` oder Push auf `main` unter `patches/**`), Artifact als `tar.xz`. Kalt ca. 45 min, mit ccache ca. 13 min.
- `gh` aus anderem cwd braucht `-R jonathanglasmeyer/bedrock-mac`.
- `patches/winegdk/*.patch` werden per `git apply` in Glob-Reihenfolge auf den gepinnten WineGDK-Commit `75637b6` angewendet. Neue Patches vorher lokal gegen einen frischen Clone mit allen vorherigen Patches prüfen.
- Smoke-Test einer neuen Runtime: `WINEPREFIX=<prefix> <runtime>/bin/wine cmd /c ver`. Der erste Lauf aktualisiert den Prefix und kann über 90 s dauern.

## GS-Register auf macOS (Patch 0105)

- GSBASE bleibt auf dem pthread-TSD, D3DMetal braucht das. Nicht wieder auf den TEB umschalten.
- Wine darf nur TSD-Slot 6 (`%gs:0x30`, `TEB.Self`) und 11 (`%gs:0x58`, `ThreadLocalStoragePointer`) beschreiben. Slot 12 (`%gs:0x60`) gehört der libc, PEB und andere TEB-Felder immer über `%gs:0x30` + Offset lesen.
- Änderungen an `ThreadLocalStoragePointer` müssen in die TSD-Kopie gespiegelt werden (`teb->Instrumentation[0]`, siehe `loader.c` im Patch).

## Starten und Debuggen

- `./bedrock.sh`, Backend per `BEDROCK_GRAPHICS=d3dmetal|dxmt` oder Datei `~/Games/bedrock-mac/graphics`. Andere Runtime per `BEDROCK_RUNTIME`.
- Logs: `~/Games/bedrock-mac/logs/minecraft-*.log`. `WINEDEBUG` wird durchgereicht, z. B. `+loaddll,+seh`.
- FPS: `MTL_HUD_ENABLED=1`.
