#!/usr/bin/env bash
set -euo pipefail

for cmd in curl python3 dpkg dpkg-deb sha256sum pkexec apt-get; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[edge] missing prerequisite: $cmd" >&2; exit 1; }
done

if command -v microsoft-edge >/dev/null 2>&1; then
  echo "[edge] already installed: $(microsoft-edge --version)"
else
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  PACKAGES_URL="https://packages.microsoft.com/repos/edge/dists/stable/main/binary-amd64/Packages.gz"
  curl -fsSL "$PACKAGES_URL" -o "$TMP/Packages.gz"
  python3 - "$TMP/Packages.gz" "$TMP/meta.json" <<'PY'
import gzip, json, subprocess, sys
text=gzip.open(sys.argv[1],"rt",encoding="utf-8",errors="replace").read()
items=[]
for stanza in text.strip().split("\n\n"):
    d={}
    for line in stanza.splitlines():
        if ": " in line:
            k,v=line.split(": ",1)
            d[k]=v
    if d.get("Package")=="microsoft-edge-stable" and d.get("Architecture")=="amd64":
        items.append(d)
if not items:
    raise SystemExit("microsoft-edge-stable amd64 not found")
best=items[0]
for item in items[1:]:
    if subprocess.run(["dpkg","--compare-versions",item["Version"],"gt",best["Version"]]).returncode==0:
        best=item
out={k:best[k] for k in ("Package","Version","Filename","SHA256","Architecture")}
open(sys.argv[2],"w").write(json.dumps(out))
print("[edge] selected",out["Version"])
PY
  FILE="$(python3 -c "import json; print(json.load(open('$TMP/meta.json'))['Filename'])")"
  SHA="$(python3 -c "import json; print(json.load(open('$TMP/meta.json'))['SHA256'])")"
  curl -fL "https://packages.microsoft.com/repos/edge/$FILE" -o "$TMP/microsoft-edge-stable.deb"
  printf "%s  %s\n" "$SHA" "$TMP/microsoft-edge-stable.deb" | sha256sum -c -
  echo "[edge] Ubuntu authentication is required to install the verified package."
  pkexec /bin/sh -c "apt-get install -y '$TMP/microsoft-edge-stable.deb'"
fi

EXTENSION_URL="https://chromewebstore.google.com/detail/interpreter-chrome-extens/bboaaphdpllilofamfpommlbafpellnb"
echo "[edge] Interpreter extension: $EXTENSION_URL"
if [[ -n "${DISPLAY:-}" ]]; then
  microsoft-edge --new-window "$EXTENSION_URL" >/dev/null 2>&1 &
fi
