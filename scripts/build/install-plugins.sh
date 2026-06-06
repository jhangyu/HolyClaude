#!/usr/bin/env bash
# Original section: CloudCLI plugin install logic
#
# Writes the plugin manifest JSON and ensures correct ownership. Requires the
# plugin files to already be present at /home/claude/.claude-code-ui/plugins,
# which is populated by a Dockerfile `COPY --from=cloudcli-plugin-builder`
# directive that must run before this script.

set -euo pipefail

echo '{"project-stats":{"name":"project-stats","source":"https://github.com/cloudcli-ai/cloudcli-plugin-starter","enabled":true},"web-terminal":{"name":"web-terminal","source":"https://github.com/cloudcli-ai/cloudcli-plugin-terminal","enabled":true}}' > /home/claude/.claude-code-ui/plugins.json
chown claude:claude /home/claude/.claude-code-ui/plugins.json
