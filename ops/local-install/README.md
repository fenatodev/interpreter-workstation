# Local Interpreter restore kit

This directory reproduces the known-good Ubuntu workstation setup without storing credentials.

## Exact reference

- Branch: `interpreter-stable`
- Restore-ready tag: `known-good-2026-10-05-restore-ready`
- Open Interpreter/OIX: 0.0.55
- Linux Computer Use: 0.7.10
- Node: 22.23.3
- pnpm: 9.15.9
- Bun: 1.4.2
- GitHub CLI: 2.102.0

## Fresh restore

Base Ubuntu requirements: `git`, `curl`, `tar`, `sha256sum`, `python3`, and `xz-utils`.

```bash
mkdir -p /mnt/infra/apps
git clone --branch interpreter-stable https://github.com/fenatodev/interpreter-workstation.git /mnt/infra/apps/interpreter-workstation
cd /mnt/infra/apps/interpreter-workstation
git fetch --tags
git reset --hard known-good-2026-10-05-restore-ready
./ops/local-install/restore.sh apply
```

The script installs the pinned user-space toolchain, verified OIX and Computer Use binaries, GitHub CLI, the launcher, desktop entry, DeepSeek proxy, safe Interpreter settings, autonomy policy, MCP defaults, the DeepSeek Flash profile, and builds/starts Workstation.

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
