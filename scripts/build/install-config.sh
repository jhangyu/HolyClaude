#!/usr/bin/env bash
# Original section: config files install
#
# Copies the runtime entrypoint, bootstrap, and notification scripts plus the
# default configuration files into their final locations under /usr/local.
# Expects /tmp/scripts/ and /tmp/config/ to be staged by the Dockerfile.

set -euo pipefail

# ---------- Copy entrypoint and bootstrap scripts ----------
cp /tmp/scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
cp /tmp/scripts/bootstrap.sh /usr/local/bin/bootstrap.sh
cp /tmp/scripts/notify.py /usr/local/bin/notify.py

# ---------- Copy config files ----------
mkdir -p /usr/local/share/holyclaude
cp /tmp/config/settings.json /usr/local/share/holyclaude/settings.json
cp /tmp/config/claude-memory-full.md /usr/local/share/holyclaude/claude-memory-full.md
cp /tmp/config/claude-memory-slim.md /usr/local/share/holyclaude/claude-memory-slim.md

# ---------- Set executable bits ----------
chmod +x /usr/local/bin/entrypoint.sh \
    /usr/local/bin/bootstrap.sh \
    /usr/local/bin/notify.py
