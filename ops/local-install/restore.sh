#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-apply}"
case "$MODE" in
  apply|check) ;;
  *) echo "usage: $0 [apply|check]" >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
KIT="$ROOT/ops/local-install"
HOME_DIR="${HOME:?HOME is required}"
LOCAL_BIN="$HOME_DIR/.local/bin"
LOCAL_LIB="$HOME_DIR/.local/lib"
CONFIG_DIR="$HOME_DIR/.config/interpreter"
OPENI_DIR="$HOME_DIR/.openinterpreter"
SECRET_FILE="$OPENI_DIR/secrets/deepseek.env"
CU_VERSION="0.7.10"
CU_ASSET="computer-use-linux-x86_64-unknown-linux-gnu"
CU_BASE="https://github.com/agent-sh/computer-use-linux/releases/download/v${CU_VERSION}"
GH_VERSION="2.102.0"
GH_ASSET="gh_${GH_VERSION}_linux_amd64.tar.gz"
GH_BASE="https://github.com/cli/cli/releases/download/v${GH_VERSION}"
NODE_VERSION="22.23.3"
PNPM_VERSION="9.15.9"
BUN_VERSION="1.4.2"
WHISPER_VERSION="1.9.4"
WHISPER_REPO="https://github.com/ggml-org/whisper.cpp.git"
WHISPER_ROOT="$(dirname "$ROOT")/whisper.cpp"
WHISPER_MODEL_NAME="ggml-large-v3-turbo-q5_0.bin"
WHISPER_MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$WHISPER_MODEL_NAME"
WHISPER_MODEL_SHA256="394221709cd5ad1f40c46e6031ca61bce88931e6e088c188294c6d5a55ffa7e2"
TTS_FAST_PTBR_MODEL_ID="vits-piper-pt_BR-faber-medium"
TTS_QUALITY_PTBR_MODEL_ID="kokoro-pt_BR-dora-v1_0"
EXPECTED_TAG="known-good-2026-10-05-fast-voice"

log() { printf "[restore] %s\n" "$*"; }
die() { printf "[restore] ERROR: %s\n" "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing base prerequisite: $1"; }

export PATH="$LOCAL_BIN:$HOME_DIR/.bun/bin:$PATH"

for cmd in git curl tar sha256sum python3 xz apt-get; do need "$cmd"; done

if [[ "$MODE" == "check" ]]; then
  log "repo=$ROOT"
  log "head=$(git -C "$ROOT" rev-parse --short HEAD)"
  log "branch=$(git -C "$ROOT" branch --show-current)"
  [[ -x "$LOCAL_BIN/interpreter" ]] && "$LOCAL_BIN/interpreter" --version || log "interpreter=missing"
  [[ -x "$LOCAL_BIN/computer-use-linux" ]] && "$LOCAL_BIN/computer-use-linux" doctor >/dev/null 2>&1 && log "computer-use-linux=ok" || log "computer-use-linux=missing-or-not-ready"
  [[ -x "$LOCAL_BIN/gh" ]] && "$LOCAL_BIN/gh" auth status -h github.com >/dev/null 2>&1 && log "gh=authenticated" || log "gh=needs-auth"
  [[ -s "$SECRET_FILE" ]] && log "deepseek-secret=present" || log "deepseek-secret=needs-restore"
  if curl -fsS --max-time 3 http://127.0.0.1:1253/models >/dev/null 2>&1; then
    log "deepseek-proxy=ready"
  else
    log "deepseek-proxy=not-ready"
  fi
  [[ -f "$CONFIG_DIR/main-window-state.json" ]] && log "window-state=present" || log "window-state=will-be-created-on-use"
  CHECK_WHISPER_BIN="$WHISPER_ROOT/build-vulkan/bin/whisper-cli"
  CHECK_WHISPER_MODEL="$WHISPER_ROOT/models/$WHISPER_MODEL_NAME"
  if [[ -x "$CHECK_WHISPER_BIN" && -f "$CHECK_WHISPER_MODEL" ]]; then
    if printf "%s  %s\\n" "$WHISPER_MODEL_SHA256" "$CHECK_WHISPER_MODEL" | sha256sum -c - >/dev/null 2>&1; then
      log "whisper-stt=ready"
    else
      log "whisper-stt=model-hash-mismatch"
    fi
  else
    log "whisper-stt=missing"
  fi
  if curl -fsS --max-time 3 http://127.0.0.1:1264/ >/dev/null 2>&1; then
    log "whisper-server=ready"
  else
    log "whisper-server=not-ready"
  fi
  [[ -f "$CONFIG_DIR/tts-models/vits-piper-pt_BR-faber-medium/vits-piper-pt_BR-faber-medium/pt_BR-faber-medium.onnx" ]] \
    && log "tts-faber-ptbr=installed" \
    || log "tts-faber-ptbr=missing"
  [[ -f "$CONFIG_DIR/tts-models/kokoro-pt_BR-dora-v1_0/kokoro-multi-lang-v1_0/model.onnx" ]] \
    && log "tts-kokoro-ptbr=installed" \
    || log "tts-kokoro-ptbr=missing"
  if curl -fsS --max-time 2 http://127.0.0.1:5177/api/profiles >/dev/null 2>&1; then
    python3 - <<'PY'
import json, urllib.request
for namespace in ("tts","stt"):
    req=urllib.request.Request(
        f"http://127.0.0.1:5177/api/ipc/{namespace}/getSettings",
        data=b"[]",
        headers={"Content-Type":"application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req,timeout=10) as resp:
        payload=json.loads(resp.read().decode()).get("settings",{})
    print(f"[restore] {namespace}-settings={json.dumps(payload,ensure_ascii=False,separators=(',',':'))}")
PY
  fi
  exit 0
fi

mkdir -p "$LOCAL_BIN" "$LOCAL_LIB" "$HOME_DIR/.bun/bin" "$CONFIG_DIR" "$OPENI_DIR/secrets"

git -C "$ROOT" config user.name "fenatodev"
git -C "$ROOT" config user.email "69322763+fenatodev@users.noreply.github.com"
if git -C "$ROOT" remote get-url upstream >/dev/null 2>&1; then
  git -C "$ROOT" remote set-url upstream https://github.com/openinterpreter/interpreter-workstation.git
else
  git -C "$ROOT" remote add upstream https://github.com/openinterpreter/interpreter-workstation.git
fi
git -C "$ROOT" remote set-url --push upstream DISABLED

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! command -v node >/dev/null 2>&1 || [[ "$(node --version 2>/dev/null || true)" != "v$NODE_VERSION" ]]; then
  log "installing Node v$NODE_VERSION"
  NODE_ASSET="node-v$NODE_VERSION-linux-x64.tar.xz"
  NODE_BASE="https://nodejs.org/dist/v$NODE_VERSION"
  curl -fsSL "$NODE_BASE/$NODE_ASSET" -o "$TMP/$NODE_ASSET"
  curl -fsSL "$NODE_BASE/SHASUMS256.txt" -o "$TMP/node-shasums.txt"
  EXPECTED_NODE="$(awk -v f="$NODE_ASSET" '$2==f {print $1}' "$TMP/node-shasums.txt")"
  [[ -n "$EXPECTED_NODE" ]] || die "Node checksum entry not found"
  printf "%s  %s\n" "$EXPECTED_NODE" "$TMP/$NODE_ASSET" | sha256sum -c -
  rm -rf "$LOCAL_LIB/node-v$NODE_VERSION-linux-x64"
  tar -xJf "$TMP/$NODE_ASSET" -C "$LOCAL_LIB"
  for bin in node npm npx corepack; do
    ln -sfn "$LOCAL_LIB/node-v$NODE_VERSION-linux-x64/bin/$bin" "$LOCAL_BIN/$bin"
  done
fi

if ! command -v pnpm >/dev/null 2>&1 || [[ "$(pnpm --version 2>/dev/null || true)" != "$PNPM_VERSION" ]]; then
  log "installing pnpm $PNPM_VERSION"
  npm install --global --prefix "$HOME_DIR/.local" "pnpm@$PNPM_VERSION"
fi

if ! command -v bun >/dev/null 2>&1 || [[ "$(bun --version 2>/dev/null || true)" != "$BUN_VERSION" ]]; then
  log "installing Bun $BUN_VERSION"
  BUN_ASSET="bun-linux-x64.zip"
  BUN_BASE="https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION"
  curl -fsSL "$BUN_BASE/$BUN_ASSET" -o "$TMP/$BUN_ASSET"
  curl -fsSL "$BUN_BASE/SHASUMS256.txt" -o "$TMP/bun-shasums.txt"
  EXPECTED_BUN="$(awk -v f="$BUN_ASSET" '$2==f {print $1}' "$TMP/bun-shasums.txt")"
  [[ -n "$EXPECTED_BUN" ]] || die "Bun checksum entry not found"
  printf "%s  %s\n" "$EXPECTED_BUN" "$TMP/$BUN_ASSET" | sha256sum -c -
  python3 - "$TMP/$BUN_ASSET" "$TMP" <<'PY'
import pathlib, sys, zipfile
archive=pathlib.Path(sys.argv[1])
dest=pathlib.Path(sys.argv[2])
with zipfile.ZipFile(archive) as zf:
    zf.extractall(dest)
PY
  install -m 0755 "$TMP/bun-linux-x64/bun" "$HOME_DIR/.bun/bin/bun"
fi
hash -r

log "installing repo dependencies"
pnpm -C "$ROOT" install --frozen-lockfile

log "preparing Whisper.cpp Vulkan runtime"
missing_whisper_dep=0
for cmd in cmake ninja glslc c++; do
  command -v "$cmd" >/dev/null 2>&1 || missing_whisper_dep=1
done
command -v pkg-config >/dev/null 2>&1 || missing_whisper_dep=1
if command -v pkg-config >/dev/null 2>&1; then
  pkg-config --exists vulkan >/dev/null 2>&1 || missing_whisper_dep=1
fi
if [[ "$missing_whisper_dep" == "1" ]]; then
  command -v pkexec >/dev/null 2>&1 || die "Whisper Vulkan build dependencies are missing and pkexec is unavailable"
  log "installing Whisper Vulkan build dependencies (Ubuntu authentication required)"
  pkexec apt-get update
  pkexec apt-get install -y build-essential cmake ninja-build glslc libvulkan-dev pkg-config
fi

if [[ ! -d "$WHISPER_ROOT/.git" ]]; then
  git clone --branch "v$WHISPER_VERSION" --depth 1 "$WHISPER_REPO" "$WHISPER_ROOT"
else
  git -C "$WHISPER_ROOT" fetch --tags --depth 1 origin "v$WHISPER_VERSION"
  git -C "$WHISPER_ROOT" checkout -f "v$WHISPER_VERSION"
fi
cmake -S "$WHISPER_ROOT" -B "$WHISPER_ROOT/build-vulkan" -G Ninja   -DGGML_VULKAN=ON -DCMAKE_BUILD_TYPE=Release
cmake --build "$WHISPER_ROOT/build-vulkan" -j "$(nproc)"

WHISPER_MODEL_PATH="$WHISPER_ROOT/models/$WHISPER_MODEL_NAME"
mkdir -p "$WHISPER_ROOT/models"
if [[ ! -f "$WHISPER_MODEL_PATH" ]]   || ! printf "%s  %s
" "$WHISPER_MODEL_SHA256" "$WHISPER_MODEL_PATH" | sha256sum -c - >/dev/null 2>&1; then
  log "downloading Whisper large-v3-turbo q5 model"
  curl -fL --retry 3 --retry-delay 2 "$WHISPER_MODEL_URL" -o "$WHISPER_MODEL_PATH.tmp"
  printf "%s  %s
" "$WHISPER_MODEL_SHA256" "$WHISPER_MODEL_PATH.tmp" | sha256sum -c -
  mv "$WHISPER_MODEL_PATH.tmp" "$WHISPER_MODEL_PATH"
fi
"$WHISPER_ROOT/build-vulkan/bin/whisper-cli" --version >/dev/null 2>&1   || die "Whisper CLI validation failed"

log "downloading pinned OIX runtime"
pnpm -C "$ROOT" run download:oix -- --current-platform
OIX_BIN="$ROOT/resources/oix/linux-x64/bin/interpreter"
[[ -x "$OIX_BIN" ]] || die "OIX binary missing after download: $OIX_BIN"
[[ "$("$OIX_BIN" --version 2>/dev/null)" == *"0.0.55"* ]] || die "unexpected OIX version"
ln -sfn "$OIX_BIN" "$LOCAL_BIN/interpreter"

log "installing computer-use-linux v$CU_VERSION"
curl -fsSL "$CU_BASE/$CU_ASSET" -o "$TMP/$CU_ASSET"
curl -fsSL "$CU_BASE/$CU_ASSET.sha256" -o "$TMP/$CU_ASSET.sha256"
(cd "$TMP" && sha256sum -c "$CU_ASSET.sha256")
install -m 0755 "$TMP/$CU_ASSET" "$LOCAL_BIN/computer-use-linux"

log "preparing Linux Computer Use"
"$LOCAL_BIN/computer-use-linux" setup >"$TMP/computer-use-setup.json" 2>&1 || log "computer-use setup reported a non-fatal warning"
"$LOCAL_BIN/computer-use-linux" setup-window-targeting >"$TMP/computer-use-window-targeting.json" 2>&1 || log "window targeting setup reported a non-fatal warning"
python3 - "$TMP/computer-use-window-targeting.json" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1])
try:
    data=json.loads(p.read_text())
except Exception:
    raise SystemExit(0)
if data.get("requires_shell_reload"):
    print("[restore] ACTION REQUIRED: log out and back in once so GNOME window targeting becomes active")
PY

log "installing gh $GH_VERSION"
curl -fsSL "$GH_BASE/$GH_ASSET" -o "$TMP/$GH_ASSET"
curl -fsSL "$GH_BASE/gh_${GH_VERSION}_checksums.txt" -o "$TMP/gh-checksums.txt"
EXPECTED_GH="$(awk -v f="$GH_ASSET" '$2==f {print $1}' "$TMP/gh-checksums.txt")"
[[ -n "$EXPECTED_GH" ]] || die "gh checksum entry not found"
printf "%s  %s\n" "$EXPECTED_GH" "$TMP/$GH_ASSET" | sha256sum -c -
tar -xzf "$TMP/$GH_ASSET" -C "$TMP"
install -m 0755 "$TMP/gh_${GH_VERSION}_linux_amd64/bin/gh" "$LOCAL_BIN/gh"

log "installing launcher, desktop entry and DeepSeek proxy"
install -m 0755 "$KIT/files/open-interpreter-workstation" "$LOCAL_BIN/open-interpreter-workstation"
install -m 0644 "$KIT/files/deepseek-responses-proxy.mjs" "$LOCAL_LIB/deepseek-responses-proxy.mjs"

NODE_BIN="$(command -v node)"
USER_SYSTEMD_DIR="$HOME_DIR/.config/systemd/user"
mkdir -p "$USER_SYSTEMD_DIR"
sed -e "s|__HOME__|$HOME_DIR|g" -e "s|__NODE__|$NODE_BIN|g" \
  "$KIT/templates/deepseek-responses-proxy.service" \
  > "$USER_SYSTEMD_DIR/deepseek-responses-proxy.service"
chmod 0644 "$USER_SYSTEMD_DIR/deepseek-responses-proxy.service"
sed -e "s|__WHISPER_ROOT__|$WHISPER_ROOT|g" \
  "$KIT/templates/interpreter-whisper.service" \
  > "$USER_SYSTEMD_DIR/interpreter-whisper.service"
chmod 0644 "$USER_SYSTEMD_DIR/interpreter-whisper.service"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
if command -v systemctl >/dev/null 2>&1 && systemctl --user daemon-reload >/dev/null 2>&1; then
  systemctl --user enable --now deepseek-responses-proxy.service >/dev/null 2>&1 \
    || log "DeepSeek proxy service could not be started; launcher fallback will be used"
  systemctl --user enable --now interpreter-whisper.service >/dev/null 2>&1 \
    || die "Whisper STT service could not be started"
else
  log "user systemd unavailable; launcher fallback will be used for DeepSeek proxy"
  log "ACTION REQUIRED: start whisper-server manually on 127.0.0.1:1264"
fi

mkdir -p "$HOME_DIR/.local/share/applications"
sed "s|__HOME__|$HOME_DIR|g" "$KIT/templates/open-interpreter.desktop" > "$HOME_DIR/.local/share/applications/open-interpreter.desktop"
chmod 0644 "$HOME_DIR/.local/share/applications/open-interpreter.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME_DIR/.local/share/applications" >/dev/null 2>&1 || true

log "merging safe Interpreter configuration"
python3 - "$KIT/templates/interpreter-config.safe.json" "$CONFIG_DIR/config.json" "$HOME_DIR" <<'PY'
import json, pathlib, sys
template_path=pathlib.Path(sys.argv[1])
target_path=pathlib.Path(sys.argv[2])
home=sys.argv[3]
template=json.loads(template_path.read_text())
target=json.loads(target_path.read_text()) if target_path.exists() else {}

def expand(v):
    if isinstance(v,str):
        return v.replace("__HOME__",home)
    if isinstance(v,list):
        return [expand(x) for x in v]
    if isinstance(v,dict):
        return {k:expand(x) for k,x in v.items()}
    return v

template=expand(template)
for key in ("customInstructions","codexSandboxMode","codexReadAccessMode","codexApprovalPolicy","cuaAccessPolicy"):
    target[key]=template[key]
target.setdefault("builtinToolsEnabled",{}).update(template["builtinToolsEnabled"])
target.setdefault("mcpServers",{})
for sid,server in template["mcpServers"].items():
    current=target["mcpServers"].get(sid,{})
    current.update(server)
    target["mcpServers"][sid]=current
target_path.parent.mkdir(parents=True,exist_ok=True)
target_path.write_text(json.dumps(target,ensure_ascii=False,indent=2)+"\n")
PY
chmod 0600 "$CONFIG_DIR/config.json"

log "building Workstation"
pnpm -C "$ROOT" run build

HEALTH_URL="http://127.0.0.1:5177/api/profiles"
if ! curl -fsS --max-time 2 "$HEALTH_URL" >/dev/null 2>&1; then
  log "starting Workstation"
  nohup "$LOCAL_BIN/open-interpreter-workstation" >/dev/null 2>&1 &
fi
for _ in $(seq 1 60); do
  curl -fsS --max-time 2 "$HEALTH_URL" >/dev/null 2>&1 && break
  sleep 0.5
done
curl -fsS --max-time 2 "$HEALTH_URL" >/dev/null || die "Workstation did not start"

log "applying native autonomy policy"
python3 - <<'PY'
import json, urllib.request
base="http://127.0.0.1:5177/api/ipc/nativeTools"
for method,payload in [
    ("setReadAccessMode",["full-system"]),
    ("setApprovalPolicy",["on-request"]),
    ("setSandboxMode",["danger-full-access"]),
    ("setNetworkAccess",[True]),
    ("setCuaAccessPolicy",[{"permissions":{"inspect":{"mode":"all"},"control":{"mode":"all"}},"appPolicies":[]}]),
]:
    req=urllib.request.Request(f"{base}/{method}",data=json.dumps(payload).encode(),headers={"Content-Type":"application/json"},method="POST")
    urllib.request.urlopen(req,timeout=15).read()
PY

log "ensuring DeepSeek Flash profile"
python3 - <<'PY'
import json, urllib.error, urllib.request
base="http://127.0.0.1:5177"
profile={
    "id":"custom:1791188697771",
    "name":"DeepSeek Flash",
    "provider":"api",
    "modelId":"deepseek-flash",
    "isBuiltin":False,
    "environmentKey":"DEEPSEEK_API_KEY",
    "baseURL":"http://127.0.0.1:1253",
    "codexProfileId":"deepseek",
    "harness":"native",
    "apiFormat":"openai",
    "wireApi":"responses",
    "useResponsesApi":True,
    "apiKey":"local-proxy",
}
def request(method,path,payload=None):
    data=None if payload is None else json.dumps(payload).encode()
    req=urllib.request.Request(
        base+path,
        data=data,
        headers={"Content-Type":"application/json"},
        method=method,
    )
    with urllib.request.urlopen(req,timeout=20) as resp:
        return json.loads(resp.read().decode())
try:
    request("GET","/api/profiles/"+profile["id"])
except urllib.error.HTTPError as e:
    if e.code != 404:
        raise
    request("POST","/api/profiles",profile)
else:
    request("PATCH","/api/profiles/"+profile["id"],profile)
request("POST","/api/profiles/default",{"profileId":profile["id"]})
PY

log "installing and configuring local voice"
python3 - <<'PY'
import json, urllib.request
base="http://127.0.0.1:5177/api/ipc"

def post(path,payload,timeout=60):
    req=urllib.request.Request(
        base+path,
        data=json.dumps(payload).encode(),
        headers={"Content-Type":"application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req,timeout=timeout) as resp:
        return json.loads(resp.read().decode())

fast_model_id="vits-piper-pt_BR-faber-medium"
quality_model_id="kokoro-pt_BR-dora-v1_0"
models=post("/tts/listModels",[])
by_id={item.get("id"):item for item in models.get("models",[])}

for model_id in (fast_model_id,quality_model_id):
    model=by_id.get(model_id)
    if not model:
        raise RuntimeError(f"pt-BR TTS model missing from catalog: {model_id}")
    if not model.get("installed"):
        result=post("/tts/installModel",[{"modelId":model_id}],timeout=900)
        if not result.get("success"):
            raise RuntimeError(result.get("error") or f"pt-BR TTS install failed: {model_id}")

fast_voices=post("/tts/getVoices",[{"modelId":fast_model_id}],timeout=180)
if not any(item.get("id")==0 for item in fast_voices.get("voices",[])):
    raise RuntimeError("Faber pt-BR voiceId 0 unavailable")
quality_voices=post("/tts/getVoices",[{"modelId":quality_model_id}],timeout=180)
if not any(item.get("id")==42 for item in quality_voices.get("voices",[])):
    raise RuntimeError("Dora pt-BR voiceId 42 unavailable")

tts=post("/tts/setSettings",[{"settings":{
    "readAssistantMessages":True,
    "modelId":fast_model_id,
    "voiceId":0,
    "speed":1.12,
    "pitch":0,
    "provider":"cpu",
    "autotuneEnabled":False,
}}])
if not tts.get("success"):
    raise RuntimeError(tts.get("error") or "failed to configure TTS")

stt=post("/stt/setSettings",[{"settings":{
    "backend":"whisper",
    "stripChineseCharacters":True,
    "silenceTimeoutMs":1800,
    "fastSentenceSilenceTimeoutMs":700,
    "previewBeforeSendMs":650,
    "sendCommand":"enviar",
    "newChatCommand":"nova conversa",
    "voiceMode":"push-to-talk",
    "ambientTriggerPhrases":["Interpreter","Intérprete","Interprete"],
    "ambientEndPhrases":["enviar","pronto"],
}}])
if not stt.get("success"):
    raise RuntimeError(stt.get("error") or "failed to configure STT")
print("[restore] TTS=Faber pt-BR fast default + Kokoro quality voices; STT=Whisper push-to-talk")
PY

log "applying MCP defaults"
python3 - <<'PY'
import json, urllib.request
url="http://127.0.0.1:5177/api/ipc/servers/toggle"
for sid,enabled in [("linux-computer-use",True),("codex_apps",False)]:
    req=urllib.request.Request(url,data=json.dumps([sid,enabled]).encode(),headers={"Content-Type":"application/json"},method="POST")
    urllib.request.urlopen(req,timeout=60).read()
PY

log "restore complete"
if ! "$LOCAL_BIN/gh" auth status -h github.com >/dev/null 2>&1; then
  log "ACTION REQUIRED: gh auth login --hostname github.com --git-protocol https --web"
else
  "$LOCAL_BIN/gh" auth setup-git >/dev/null 2>&1 || true
fi
[[ -s "$SECRET_FILE" ]] || log "ACTION REQUIRED: restore DEEPSEEK_API_KEY in $SECRET_FILE and chmod 600 it"
log "ACTION REQUIRED after a clean reinstall: relink WhatsApp from Dispatch by scanning a new QR"
log "known-good reference: $EXPECTED_TAG"
