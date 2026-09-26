#!/usr/bin/env python3
"""Einmalige Microsoft-Anmeldung für Minecraft Bedrock auf dem Mac.

Holt per Gerätecode (Code im Browser eingeben) einen MSA-Refresh-Token für die
Minecraft-Client-ID. WineGDKs XUser liest ihn aus
HKLM\\Software\\Wine\\WineGDK "RefreshToken" und macht den Xbox-Live-/XSTS-
Austausch selbst; bedrock.sh trägt ihn beim Start in den Prefix ein.

Ablauf und Konstanten wie in BedrockOnLinux (bol/auth.py, MIT).

  ./xbox-login.py            anmelden
  ./xbox-login.py --logout   Token löschen
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CLIENT_ID = "0000000048183522"
SCOPE = "service::user.auth.xboxlive.com::MBI_SSL"
CONNECT = "https://login.live.com/oauth20_connect.srf"
TOKEN = "https://login.live.com/oauth20_token.srf"

HOME = Path(os.environ.get("BEDROCK_HOME", Path.home() / "Games/bedrock-mac"))
TOKEN_FILE = HOME / "msa-refresh-token"


def post(url, fields):
    req = urllib.request.Request(
        url, data=urllib.parse.urlencode(fields).encode(), method="POST",
        headers={"Accept": "application/json",
                 "Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode())


def save(token):
    HOME.mkdir(parents=True, exist_ok=True)
    fd = os.open(TOKEN_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(token)


def main():
    if "--logout" in sys.argv:
        TOKEN_FILE.unlink(missing_ok=True)
        print("Abgemeldet. bedrock.sh entfernt den Token beim nächsten Start aus dem Prefix.")
        return

    d = post(CONNECT, {"client_id": CLIENT_ID, "scope": SCOPE,
                       "response_type": "device_code"})
    if "device_code" not in d:
        sys.exit(f"Gerätecode-Anfrage fehlgeschlagen: {d.get('error_description') or d}")

    url = d.get("verification_uri") or "https://www.microsoft.com/link"
    print(f"\nÖffne {url} und gib diesen Code ein:\n\n    {d['user_code']}\n")
    if sys.platform == "darwin":
        os.system(f"open '{url}' >/dev/null 2>&1")

    interval = max(int(d.get("interval", 5)), 1)
    deadline = time.time() + int(d.get("expires_in", 900))
    while time.time() < deadline:
        time.sleep(interval)
        # Legacy-live.com-Grant ohne Scope, genau wie WineGDKs XUser.c
        t = post(TOKEN, {"client_id": CLIENT_ID, "grant_type": "device_code",
                         "device_code": d["device_code"]})
        err = t.get("error")
        if err == "authorization_pending":
            continue
        if err == "slow_down":
            interval += 5
            continue
        if err:
            sys.exit(f"Anmeldung fehlgeschlagen: {t.get('error_description') or err}")
        if t.get("refresh_token"):
            save(t["refresh_token"])
            print(f"Angemeldet. Token liegt in {TOKEN_FILE}, jetzt ./bedrock.sh starten.")
            return
    sys.exit("Zeit abgelaufen, bitte nochmal starten.")


if __name__ == "__main__":
    main()
