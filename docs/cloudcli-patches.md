# CloudCLI Patch Matrix

This document records the CloudCLI fixes carried by this fork, the upstream
HolyClaude patches that inspired them, and the current status against the npm
package used by this image.

## Current CloudCLI Surface

- Package: `@cloudcli-ai/cloudcli`
- Observed version during the probe build: `1.33.1`
- Install root: `/usr/local/lib/node_modules/@cloudcli-ai/cloudcli`
- Main browser bundle observed during the probe build:
  `dist/assets/index-BsyL_xmI.js`
- Server runtime output path:
  `dist-server/server`

The browser bundle filename is content-hashed. Dockerfile patches must discover
it with `find "$CLOUDCLI_ROOT/dist/assets" -name 'index-*.js'` instead of using
a hard-coded filename.

## Applied Or Verified Fixes

| Fix | Current status | Implementation | Verification |
| --- | --- | --- | --- |
| Claude session titles | Applied | `scripts/fix-cloudcli-session-titles.py` patches the installed Claude session synchronizer and supports runtime backfill. | Build prints the patched synchronizer path. |
| Plugin WebSocket binary frame relay | Already present upstream in `@cloudcli-ai/cloudcli@1.33.1`; Dockerfile verifies it fail-closed. | Dockerfile checks `dist-server/server/modules/websocket/services/plugin-websocket-proxy.service.js` for `isBinary` in both relay directions. | Probe image reported `websocket_binary=present`. |
| Shell tab scroll position | Applied by this fork. | Dockerfile patches the main browser bundle so Shell focus preserves `buffer.active.viewportY` and calls `scrollToLine(_vp)` after focus. | Probe image reported `shell_scroll=present`; `node --check` passed for the patched bundle. |
| Node base image | Applied. | `node:26.3.0-bookworm-slim` for plugin builder and runtime stages. | `docker build --check .` and slim probe build passed. |
| s6-overlay | Applied. | `S6_OVERLAY_VERSION=3.2.3.0`. | Slim probe build downloaded and extracted the overlay assets. |
| Junie CLI install method | Applied for full variant. | `@jetbrains/junie-cli@1468.30.0` is installed via npm in the full image package set. | Dockerfile parse check passed; full-image runtime check remains recommended before release. |
| `/model` model selection flow | Already present upstream in `@cloudcli-ai/cloudcli@1.33.1`; Dockerfile verifies it fail-closed. | Dockerfile checks the server commands route and main bundle for the model list action, `setClaudeModel`, model localStorage update, and custom option handling. | Probe image reported `model_flow=present`. |
| Codex lifecycle Apprise notifications | Applied by this fork. | `scripts/patch-cloudcli-apprise-notifications.mjs` patches `dist-server/server/services/notification-orchestrator.js` so Codex stop/error lifecycle events invoke `/usr/local/bin/notify.py`. | Probe image reported `apprise_lifecycle=present`; `node --check` passed. |
| Codex chat permission mode | Applied by this fork. | `scripts/patch-cloudcli-codex-permissions.mjs` patches `dist-server/server/openai-codex.js` so `HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODE` controls the default browser Codex mode. | Probe image reported `codex_permission=present`; `node --check` passed. |

## Upstream HolyClaude Patch Compatibility

Upstream `CoderLuii/HolyClaude` currently carries patches against vendored
`@siteboon/claude-code-ui@1.26.3`. Those patches are not directly portable by
path because this fork installs `@cloudcli-ai/cloudcli` from npm.

| Upstream patch | Upstream target | Current compatibility notes |
| --- | --- | --- |
| WebSocket plugin proxy binary relay | `server/index.js` in `@siteboon/claude-code-ui` | Equivalent behavior is already present in `@cloudcli-ai/cloudcli@1.33.1`, but the code moved to `dist-server/server/modules/websocket/services/plugin-websocket-proxy.service.js`. |
| Shell tab scroll position | Minified browser bundle `dist/assets/index-X3ImjnMV.js` | Still needed. Equivalent anchor in `@cloudcli-ai/cloudcli@1.33.1` is `const D=()=>{x.current?.focus()}` in the discovered main bundle. |
| `/model` newModel propagation | `server/routes/commands.js` and minified bundle | Equivalent behavior is already present in `@cloudcli-ai/cloudcli@1.33.1`; the Docker build verifies the current route and bundle anchors instead of applying the older minified patch. |
| Codex lifecycle Apprise notifications | `server/services/notification-orchestrator.js` | Ported to the current `dist-server/server/services/notification-orchestrator.js` layout. |
| Codex chat permission mode | `server/openai-codex.js` | Ported to the current `dist-server/server/openai-codex.js` layout. |

## Probe Commands

The last local probe used:

```bash
docker build --build-arg VARIANT=slim -t holyclaude:cloudcli-1.33.1-probe .
docker run --rm --entrypoint /bin/bash holyclaude:cloudcli-1.33.1-probe -lc '
  ROOT=/usr/local/lib/node_modules/@cloudcli-ai/cloudcli
  BUNDLE=$(find "$ROOT/dist/assets" -maxdepth 1 -type f -name "index-*.js" | head -n 1)
  echo "version=$(node -p "require(\"$ROOT/package.json\").version")"
  echo "bundle=$BUNDLE"
  grep -F "scrollToLine(_vp)" "$BUNDLE" >/dev/null && echo "shell_scroll=present"
  WS="$ROOT/dist-server/server/modules/websocket/services/plugin-websocket-proxy.service.js"
  grep -F "clientWs.send(data, { binary: isBinary })" "$WS" >/dev/null
  grep -F "upstream.send(data, { binary: isBinary })" "$WS" >/dev/null
  echo "websocket_binary=present"
  CODEX="$ROOT/dist-server/server/openai-codex.js"
  NOTIFY="$ROOT/dist-server/server/services/notification-orchestrator.js"
  SESSION="$ROOT/dist-server/server/modules/providers/list/claude/claude-session-synchronizer.provider.js"
  grep -F "sendAppriseLifecycleNotification" "$NOTIFY" >/dev/null && echo "apprise_lifecycle=present"
  grep -F "HOLYCLAUDE_CODEX_CHAT_PERMISSION_MODE" "$CODEX" >/dev/null && echo "codex_permission=present"
  grep -F "setClaudeModel:" "$BUNDLE" >/dev/null
  grep -F "availableOptions" "$BUNDLE" >/dev/null && echo "model_flow=present"
  grep -F "extractMeaningfulUserText" "$SESSION" >/dev/null && echo "session_titles=present"
  node --check "$BUNDLE" && echo "bundle_syntax=ok"
  node --check "$NOTIFY"
  node --check "$CODEX"
  node --check "$SESSION"
'
```

Expected output includes:

```text
version=1.33.1
shell_scroll=present
websocket_binary=present
apprise_lifecycle=present
codex_permission=present
model_flow=present
session_titles=present
bundle_syntax=ok
```

## Maintenance Rules

- Prefer fail-closed checks for patches whose behavior is already present
  upstream.
- Avoid hard-coding hashed bundle filenames.
- Keep minified-bundle patches narrow and verify with `node --check`.
- If CloudCLI changes package layout or minified symbols, stop the build rather
  than silently shipping an unpatched image.
