#!/usr/bin/env bash
# Original section: patch scripts 複製 + CloudCLI patch + probe 驗證
#
# Fork-specific CloudCLI patches and probes. This script is invoked from the
# Dockerfile after `npm i -g @cloudcli-ai/cloudcli` has run, so the package
# files in /usr/local/lib/node_modules/@cloudcli-ai/cloudcli already exist.

set -euo pipefail

# ---------- Copy patch scripts (from build context, staged at /tmp/scripts/) ----------
cp /tmp/scripts/fix-cloudcli-session-titles.py /usr/local/bin/fix-cloudcli-session-titles.py
cp /tmp/scripts/patch-cloudcli-shell-scroll.mjs /usr/local/bin/patch-cloudcli-shell-scroll.mjs
cp /tmp/scripts/patch-cloudcli-apprise-notifications.mjs /usr/local/bin/patch-cloudcli-apprise-notifications.mjs
cp /tmp/scripts/patch-cloudcli-codex-permissions.mjs /usr/local/bin/patch-cloudcli-codex-permissions.mjs
chmod +x /usr/local/bin/fix-cloudcli-session-titles.py

# ---------- CloudCLI patch: session title fix ----------
python3 /usr/local/bin/fix-cloudcli-session-titles.py --mode build

# ---------- Locate CloudCLI install paths ----------
CLOUDCLI_ROOT="/usr/local/lib/node_modules/@cloudcli-ai/cloudcli"
CLOUDCLI_CODEX="$CLOUDCLI_ROOT/dist-server/server/openai-codex.js"
CLOUDCLI_NOTIFICATIONS="$CLOUDCLI_ROOT/dist-server/server/services/notification-orchestrator.js"
CLOUDCLI_COMMANDS="$CLOUDCLI_ROOT/dist-server/server/routes/commands.js"
CLOUDCLI_WS_PROXY="$CLOUDCLI_ROOT/dist-server/server/modules/websocket/services/plugin-websocket-proxy.service.js"

# ---------- Probe: WebSocket binary frame fix (must already be present upstream) ----------
grep -Fq "upstream.on('message', (data, isBinary) =>" "$CLOUDCLI_WS_PROXY"
grep -Fq "clientWs.send(data, { binary: isBinary })" "$CLOUDCLI_WS_PROXY"
grep -Fq "clientWs.on('message', (data, isBinary) =>" "$CLOUDCLI_WS_PROXY"
grep -Fq "upstream.send(data, { binary: isBinary })" "$CLOUDCLI_WS_PROXY"
echo "[patch] CloudCLI WebSocket binary frame fix already present"

# ---------- Patch: shell scroll fix (applied to bundled index JS) ----------
CLOUDCLI_BUNDLE="$(find "$CLOUDCLI_ROOT/dist/assets" -maxdepth 1 -type f -name 'index-*.js' | head -n 1)"
test -n "$CLOUDCLI_BUNDLE"
node /usr/local/bin/patch-cloudcli-shell-scroll.mjs "$CLOUDCLI_BUNDLE"

# ---------- Probe: Claude model selection flow (must already be present upstream) ----------
grep -Fq 'action: "models"' "$CLOUDCLI_COMMANDS"
grep -Fq "setClaudeModel:" "$CLOUDCLI_BUNDLE"
grep -Fq 'localStorage.setItem("claude-model"' "$CLOUDCLI_BUNDLE"
grep -Fq "availableOptions" "$CLOUDCLI_BUNDLE"
echo "[patch] CloudCLI Claude model selection flow already present"

# ---------- Patch: notifications + codex permissions ----------
node /usr/local/bin/patch-cloudcli-apprise-notifications.mjs "$CLOUDCLI_NOTIFICATIONS"
node /usr/local/bin/patch-cloudcli-codex-permissions.mjs "$CLOUDCLI_CODEX"
node --check "$CLOUDCLI_NOTIFICATIONS"
node --check "$CLOUDCLI_CODEX"
