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

This fork consumes `@cloudcli-ai/cloudcli` exclusively from npm; no vendored
tarballs or forked package copies are shipped in the image. Upstream
`CoderLuii/HolyClaude` historically patched a vendored `@siteboon/claude-code-ui`
artifact, but those vendored sources are not used here, so the upstream path
references are intentionally omitted from this matrix. Compatibility is
re-asserted against the installed npm package in the `Applied Or Verified Fixes`
table above.

| Upstream patch | Upstream target | Current compatibility notes |
| --- | --- | --- |
| WebSocket plugin proxy binary relay | (vendored upstream package, not used in this fork) | Equivalent behavior is already present in `@cloudcli-ai/cloudcli@1.33.1`, verified against `dist-server/server/modules/websocket/services/plugin-websocket-proxy.service.js`. |
| Shell tab scroll position | (vendored upstream package, not used in this fork) | Applied to the npm-installed CloudCLI main bundle; anchor is `const D=()=>{x.current?.focus()}` followed by `scrollToLine(_vp)` in the discovered main bundle. |
| `/model` newModel propagation | (vendored upstream package, not used in this fork) | Equivalent behavior is already present in `@cloudcli-ai/cloudcli@1.33.1`; the Docker build verifies the current route and bundle anchors instead of applying the older minified patch. |
| Codex lifecycle Apprise notifications | (vendored upstream package, not used in this fork) | Ported to the current `dist-server/server/services/notification-orchestrator.js` layout. |
| Codex chat permission mode | (vendored upstream package, not used in this fork) | Ported to the current `dist-server/server/openai-codex.js` layout. |

## Probe Commands

The probe verification logic has been extracted from the Dockerfile into
[`scripts/build/install-patches.sh`](../scripts/build/install-patches.sh).
That script runs fail-closed `grep` checks during the image build to confirm
the expected CloudCLI surface is in place, and then runs the actual patches.

Key probe anchors (from `scripts/build/install-patches.sh`):

```bash
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

# ---------- Probe: Claude model selection flow (must already be present upstream) ----------
grep -Fq 'action: "models"' "$CLOUDCLI_COMMANDS"
grep -Fq "setClaudeModel:" "$CLOUDCLI_BUNDLE"
grep -Fq 'localStorage.setItem("claude-model"' "$CLOUDCLI_BUNDLE"
grep -Fq "availableOptions" "$CLOUDCLI_BUNDLE"
echo "[patch] CloudCLI Claude model selection flow already present"
```

The shell-scroll, apprise, codex-permission, and session-title verifications
are not probe checks — they are applied by the patch scripts
(`patch-cloudcli-shell-scroll.mjs`, `patch-cloudcli-apprise-notifications.mjs`,
`patch-cloudcli-codex-permissions.mjs`, `fix-cloudcli-session-titles.py`)
invoked from `install-patches.sh`, and they are followed by
`node --check` syntax validation of the touched files.

## Maintenance Rules

- Prefer fail-closed checks for patches whose behavior is already present
  upstream.
- Avoid hard-coding hashed bundle filenames.
- Keep minified-bundle patches narrow and verify with `node --check`.
- If CloudCLI changes package layout or minified symbols, stop the build rather
  than silently shipping an unpatched image.
