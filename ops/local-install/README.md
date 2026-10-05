# Local Interpreter restore kit

This directory reproduces the known-good Ubuntu workstation setup without storing credentials.

## Exact reference

- Branch: `interpreter-stable`
- Restore-ready tag: `known-good-2026-10-05-whisper-voice`
- Open Interpreter/OIX: 0.0.55
- Linux Computer Use: 0.7.10
- Node: 22.23.3
- pnpm: 9.15.9
- Bun: 1.4.2
- GitHub CLI: 2.102.0
- STT: whisper.cpp 1.9.4 + large-v3-turbo-q5_0, Vulkan, pt-BR, full-utterance Push-to-Talk
- TTS: Kokoro pt-BR local CPU; Dora (feminina), Alex e Santa (masculinas)
- DeepSeek proxy: supervised user service with automatic restart

## Fresh restore

Base Ubuntu requirements: `git`, `curl`, `tar`, `sha256sum`, `python3`, `xz-utils`, and `apt-get`. If Vulkan build dependencies are missing, the restore script requests Ubuntu authentication once and installs `build-essential`, `cmake`, `ninja-build`, `glslc`, `libvulkan-dev`, and `pkg-config`.

```bash
mkdir -p /mnt/infra/apps
git clone --branch interpreter-stable https://github.com/fenatodev/interpreter-workstation.git /mnt/infra/apps/interpreter-workstation
cd /mnt/infra/apps/interpreter-workstation
git fetch --tags
git reset --hard known-good-2026-10-05-whisper-voice
./ops/local-install/restore.sh apply
```

The script installs the pinned user-space toolchain, verified OIX and Computer Use binaries, GitHub CLI, the launcher, desktop entry, DeepSeek proxy, safe Interpreter settings, autonomy policy, MCP defaults, the DeepSeek Flash profile, whisper.cpp with Vulkan, the verified large-v3-turbo-q5_0 model and persistent Whisper service, Kokoro pt-BR TTS, and builds/starts Workstation.

Microsoft Edge is intentionally handled by `./ops/local-install/install-edge.sh` because Ubuntu authentication is required. The helper validates the official Microsoft package, installs it through the system authentication prompt, then opens the official Interpreter Chrome Extension page; Chromium still requires one human confirmation to add the extension.

## Secrets and account sessions

These are intentionally not stored in Git.

1. DeepSeek: copy `templates/deepseek.env.example` to `~/.openinterpreter/secrets/deepseek.env`, replace the placeholder, then `chmod 600` it and restart Interpreter so the proxy loads the key.
2. GitHub: run `gh auth login --hostname github.com --git-protocol https --web`, then `gh auth setup-git`.
3. OpenAI/ChatGPT: sign in again through Interpreter when needed.
4. WhatsApp Dispatch: pair again with a QR code after a clean reinstall.

## Intended defaults

- Linux Computer Use: ON
- Codex Apps: OFF
- Filesystem: full access
- Read scope: full system
- Network: enabled
- Approval policy: on request
- Routine GUI control: enabled
- Sensitive/high-impact actions: approval required
- Window size/position: restored from the last session
- Local filesystem work: native shell/apply_patch, not Remote Desktop Commander

## Verification

```bash
./ops/local-install/check.sh
```

If Computer Use reports that the GNOME shell extension needs a reload, log out and back in once, then run the check again.

Do not commit `~/.openinterpreter`, `~/.config/interpreter`, WhatsApp auth state, OAuth state, cookies, or API keys.
