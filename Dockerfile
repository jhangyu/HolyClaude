# ==============================================================================
# HolyClaude — Pre-configured Docker Environment for Claude Code CLI + CloudCLI
# https://github.com/coderluii/holyclaude
#
# Build variants:
#   docker build -t holyclaude .                        # full (default)
#   docker build --build-arg VARIANT=slim -t holyclaude:slim .
# ==============================================================================

# ---------- CloudCLI plugins builder ----------
FROM node:26.3.0-bookworm-slim AS cloudcli-plugin-builder

ENV DEBIAN_FRONTEND=noninteractive \
    npm_config_audit=false \
    npm_config_fund=false \
    npm_config_update_notifier=false

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /plugins
RUN set -eux; \
    git clone --depth 1 https://github.com/cloudcli-ai/cloudcli-plugin-starter.git project-stats; \
    cd /plugins/project-stats; \
    npm install; \
    npm run build; \
    npm prune --omit=dev; \
    rm -rf .git src package-lock.json tsconfig.json node_modules/.cache; \
    git clone --depth 1 https://github.com/cloudcli-ai/cloudcli-plugin-terminal.git /plugins/web-terminal; \
    cd /plugins/web-terminal; \
    npm_config_nodedir=/usr/local npm install; \
    npm run build; \
    npm prune --omit=dev; \
    rm -rf .git src package-lock.json tsconfig.json node_modules/.cache; \
    npm cache clean --force; \
    rm -rf /root/.npm /root/.cache /tmp/*


# ---------- Runtime image ----------
FROM node:26.3.0-bookworm-slim

LABEL org.opencontainers.image.source=https://github.com/jhangyu/HolyClaude

# ---------- Build args ----------
ARG S6_OVERLAY_VERSION=3.2.3.0
ARG TARGETARCH
ARG VARIANT=full

# ---------- Environment ----------
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    DISPLAY=:99 \
    DBUS_SESSION_BUS_ADDRESS=disabled: \
    CHROMIUM_FLAGS="--no-sandbox --disable-gpu --disable-dev-shm-usage" \
    CHROME_PATH=/usr/bin/chromium \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    CLAUDE_CODE_USE_FOUNDRY=1 \
    npm_config_audit=false \
    npm_config_fund=false \
    npm_config_update_notifier=false

# ---------- System packages, external CLIs, s6-overlay ----------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      xz-utils curl ca-certificates \
      git wget jq ripgrep fd-find unzip zip tree tmux fzf bat bubblewrap \
      build-essential pkg-config python3 python3-pip python3-venv \
      chromium \
      fonts-liberation2 fonts-dejavu-core fonts-noto-core fonts-noto-color-emoji fonts-inter \
      locales \
      strace lsof iproute2 procps htop \
      postgresql-client redis-tools sqlite3 \
      openssh-client \
      xvfb \
      imagemagick \
      sudo; \
    if [ "$VARIANT" = "full" ]; then \
      apt-get install -y --no-install-recommends pandoc ffmpeg libvips-tools; \
    fi; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg 2>/dev/null; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends gh; \
    if [ "$VARIANT" = "full" ]; then \
      curl -sL https://aka.ms/InstallAzureCLIDeb | bash; \
    fi; \
    S6_ARCH=$(case "$TARGETARCH" in arm64) echo "aarch64";; *) echo "x86_64";; esac); \
    curl -fsSL -o /tmp/s6-overlay-noarch.tar.xz \
      "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz"; \
    curl -fsSL -o /tmp/s6-overlay-arch.tar.xz \
      "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz"; \
    tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz; \
    tar -C / -Jxpf /tmp/s6-overlay-arch.tar.xz; \
    chmod u+s /usr/bin/bwrap; \
    ln -sf /usr/bin/batcat /usr/local/bin/bat 2>/dev/null || true; \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen; \
    locale-gen; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

# ---------- Create claude user ----------
# node:26.3.0-bookworm-slim already has UID 1000 as 'node' — rename it to 'claude'
RUN set -eux; \
    usermod -l claude -d /home/claude -m node; \
    groupmod -n claude node; \
    echo "claude ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/claude; \
    chmod 0440 /etc/sudoers.d/claude; \
    mkdir -p /workspace; \
    chown claude:claude /workspace

# ---------- Cursor CLI ----------
WORKDIR /workspace
USER claude
RUN set -eux; \
    curl -fsSL https://cursor.com/install | bash; \
    rm -rf /home/claude/.npm /home/claude/.cache /tmp/*
USER root
ENV PATH="/home/claude/.local/bin:${PATH}"

COPY scripts/fix-cloudcli-session-titles.py /usr/local/bin/fix-cloudcli-session-titles.py
COPY scripts/patch-cloudcli-shell-scroll.mjs /usr/local/bin/patch-cloudcli-shell-scroll.mjs
COPY scripts/patch-cloudcli-apprise-notifications.mjs /usr/local/bin/patch-cloudcli-apprise-notifications.mjs
COPY scripts/patch-cloudcli-codex-permissions.mjs /usr/local/bin/patch-cloudcli-codex-permissions.mjs
RUN chmod +x /usr/local/bin/fix-cloudcli-session-titles.py

# ---------- npm global packages ----------
RUN set -eux; \
    packages="\
      typescript tsx \
      pnpm \
      vite esbuild \
      eslint prettier \
      serve nodemon concurrently \
      dotenv-cli \
      @anthropic-ai/claude-code@2.1.165 \
      @google/gemini-cli \
      @openai/codex@0.137.0 \
      task-master-ai \
      @cloudcli-ai/cloudcli@1.33.0"; \
    if [ "$VARIANT" = "full" ]; then \
      packages="$packages \
        wrangler vercel netlify-cli \
        pm2 \
        prisma drizzle-kit \
        eas-cli \
        lighthouse @lhci/cli \
        sharp-cli json-server http-server \
        @marp-team/marp-cli @cloudflare/next-on-pages \
        @jetbrains/junie-cli@1468.30.0 \
        opencode-ai"; \
    fi; \
    npm i -g --omit=dev --no-audit --no-fund $packages; \
    touch /usr/local/lib/node_modules/@cloudcli-ai/cloudcli/.env; \
    ln -sf /usr/local/bin/cloudcli /usr/local/bin/claude-code-ui; \
    python3 /usr/local/bin/fix-cloudcli-session-titles.py --mode build; \
    CLOUDCLI_ROOT="/usr/local/lib/node_modules/@cloudcli-ai/cloudcli"; \
    CLOUDCLI_CODEX="$CLOUDCLI_ROOT/dist-server/server/openai-codex.js"; \
    CLOUDCLI_NOTIFICATIONS="$CLOUDCLI_ROOT/dist-server/server/services/notification-orchestrator.js"; \
    CLOUDCLI_COMMANDS="$CLOUDCLI_ROOT/dist-server/server/routes/commands.js"; \
    CLOUDCLI_WS_PROXY="$CLOUDCLI_ROOT/dist-server/server/modules/websocket/services/plugin-websocket-proxy.service.js"; \
    grep -Fq "upstream.on('message', (data, isBinary) =>" "$CLOUDCLI_WS_PROXY"; \
    grep -Fq "clientWs.send(data, { binary: isBinary })" "$CLOUDCLI_WS_PROXY"; \
    grep -Fq "clientWs.on('message', (data, isBinary) =>" "$CLOUDCLI_WS_PROXY"; \
    grep -Fq "upstream.send(data, { binary: isBinary })" "$CLOUDCLI_WS_PROXY"; \
    echo "[patch] CloudCLI WebSocket binary frame fix already present"; \
    CLOUDCLI_BUNDLE="$(find "$CLOUDCLI_ROOT/dist/assets" -maxdepth 1 -type f -name 'index-*.js' | head -n 1)"; \
    test -n "$CLOUDCLI_BUNDLE"; \
    node /usr/local/bin/patch-cloudcli-shell-scroll.mjs "$CLOUDCLI_BUNDLE"; \
    grep -Fq 'action: "models"' "$CLOUDCLI_COMMANDS"; \
    grep -Fq "setClaudeModel:" "$CLOUDCLI_BUNDLE"; \
    grep -Fq 'localStorage.setItem("claude-model"' "$CLOUDCLI_BUNDLE"; \
    grep -Fq "availableOptions" "$CLOUDCLI_BUNDLE"; \
    echo "[patch] CloudCLI Claude model selection flow already present"; \
    node /usr/local/bin/patch-cloudcli-apprise-notifications.mjs "$CLOUDCLI_NOTIFICATIONS"; \
    node /usr/local/bin/patch-cloudcli-codex-permissions.mjs "$CLOUDCLI_CODEX"; \
    node --check "$CLOUDCLI_NOTIFICATIONS"; \
    node --check "$CLOUDCLI_CODEX"; \
    npm cache clean --force; \
    find /usr/local/lib/node_modules -type f -name '*.map' -delete; \
    find /usr/local/lib/node_modules -type d \( \
      -name test -o -name tests -o -name __tests__ -o \
      -name docs -o -name examples -o -name example \
    \) -prune -exec rm -rf {} +; \
    rm -rf /root/.npm /root/.cache /tmp/*

# ---------- Python packages ----------
RUN set -eux; \
    packages="\
      requests httpx beautifulsoup4 lxml \
      Pillow \
      pandas numpy \
      openpyxl python-docx \
      jinja2 pyyaml python-dotenv markdown \
      rich click tqdm \
      playwright \
      apprise"; \
    if [ "$VARIANT" = "full" ]; then \
      packages="$packages \
        reportlab weasyprint cairosvg fpdf2 PyMuPDF pdfkit img2pdf \
        xlsxwriter xlrd \
        matplotlib seaborn \
        python-pptx \
        fastapi uvicorn \
        httpie"; \
    fi; \
    pip install --no-cache-dir --break-system-packages $packages; \
    find /usr/local/lib/python3.11 /usr/lib/python3.11 -type d \( \
      -name __pycache__ -o -name test -o -name tests \
    \) -prune -exec rm -rf {} +; \
    rm -rf /root/.cache/pip /tmp/*

# ---------- CloudCLI plugins (baked into image) ----------
COPY --from=cloudcli-plugin-builder --chown=claude:claude /plugins /home/claude/.claude-code-ui/plugins
RUN set -eux; \
    echo '{"project-stats":{"name":"project-stats","source":"https://github.com/cloudcli-ai/cloudcli-plugin-starter","enabled":true},"web-terminal":{"name":"web-terminal","source":"https://github.com/cloudcli-ai/cloudcli-plugin-terminal","enabled":true}}' > /home/claude/.claude-code-ui/plugins.json; \
    chown claude:claude /home/claude/.claude-code-ui/plugins.json

# ---------- Store variant for bootstrap ----------
RUN echo "${VARIANT}" > /etc/holyclaude-variant

# ---------- Copy config files ----------
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/bootstrap.sh /usr/local/bin/bootstrap.sh
COPY scripts/notify.py /usr/local/bin/notify.py
COPY config/settings.json /usr/local/share/holyclaude/settings.json
COPY config/claude-memory-full.md /usr/local/share/holyclaude/claude-memory-full.md
COPY config/claude-memory-slim.md /usr/local/share/holyclaude/claude-memory-slim.md
RUN chmod +x /usr/local/bin/entrypoint.sh \
    /usr/local/bin/bootstrap.sh \
    /usr/local/bin/notify.py

# ---------- s6-overlay service definitions ----------
COPY s6-overlay/s6-rc.d/cloudcli/type /etc/s6-overlay/s6-rc.d/cloudcli/type
COPY s6-overlay/s6-rc.d/cloudcli/run /etc/s6-overlay/s6-rc.d/cloudcli/run
COPY s6-overlay/s6-rc.d/xvfb/type /etc/s6-overlay/s6-rc.d/xvfb/type
COPY s6-overlay/s6-rc.d/xvfb/run /etc/s6-overlay/s6-rc.d/xvfb/run
RUN chmod +x /etc/s6-overlay/s6-rc.d/cloudcli/run \
    /etc/s6-overlay/s6-rc.d/xvfb/run && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/cloudcli && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/xvfb

# ---------- Working directory ----------
WORKDIR /workspace

# ---------- Health check ----------
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -sf http://localhost:3001/ || exit 1

# ---------- s6-overlay as PID 1 ----------
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
