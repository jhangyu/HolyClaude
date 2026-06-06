# ==============================================================================
# HolyClaude — Pre-configured Docker Environment for Claude Code CLI + CloudCLI
# https://github.com/jhangyu/holyclaude
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
    npm_config_audit=false \
    npm_config_fund=false \
    npm_config_update_notifier=false \
    CLAUDE_CODE_ATTRIBUTION_HEADER=0

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

# ---------- npm global packages (non-fork portion only) ----------
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
      @cloudcli-ai/cloudcli@1.33.1"; \
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
    mkdir -p /home/claude/.local/bin && \
    ln -sf /usr/local/bin/claude /home/claude/.local/bin/claude && \
    chown -R claude:claude /home/claude/.local && \
    touch /usr/local/lib/node_modules/@cloudcli-ai/cloudcli/.env; \
    ln -sf /usr/local/bin/cloudcli /usr/local/bin/claude-code-ui; \
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

# ---------- CloudCLI plugins (baked into image) + fork install staging ----------
COPY --from=cloudcli-plugin-builder --chown=claude:claude /plugins /home/claude/.claude-code-ui/plugins
COPY scripts/ /tmp/scripts/
COPY config/ /tmp/config/
COPY scripts/build/ /tmp/build-scripts/

# ---------- Apply fork patches, plugins, and config (extracted to scripts/build/) ----------
RUN set -eux; \
    bash /tmp/build-scripts/install-patches.sh && \
    bash /tmp/build-scripts/install-plugins.sh && \
    bash /tmp/build-scripts/install-config.sh && \
    rm -rf /tmp/scripts /tmp/config /tmp/build-scripts

# ---------- Store variant for bootstrap ----------
RUN echo "${VARIANT}" > /etc/holyclaude-variant

# ---------- s6-overlay service definitions ----------
COPY s6-overlay/s6-rc.d/cloudcli/type /etc/s6-overlay/s6-rc.d/cloudcli/type
COPY s6-overlay/s6-rc.d/cloudcli/run /etc/s6-overlay/s6-rc.d/cloudcli/run
COPY s6-overlay/s6-rc.d/xvfb/type /etc/s6-overlay/s6-rc.d/xvfb/type
COPY s6-overlay/s6-rc.d/xvfb/run /etc/s6-overlay/s6-rc.d/xvfb/run
COPY s6-overlay/s6-rc.d/claude-persist/type /etc/s6-overlay/s6-rc.d/claude-persist/type
COPY s6-overlay/s6-rc.d/claude-persist/run  /etc/s6-overlay/s6-rc.d/claude-persist/run
RUN chmod +x /etc/s6-overlay/s6-rc.d/cloudcli/run \
    /etc/s6-overlay/s6-rc.d/xvfb/run \
    /etc/s6-overlay/s6-rc.d/claude-persist/run && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/cloudcli && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/xvfb && \
    touch /etc/s6-overlay/s6-rc.d/user/contents.d/claude-persist

# ---------- Working directory ----------
WORKDIR /workspace

# ---------- Health check ----------
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -sf http://localhost:3001/ || exit 1

# ---------- s6-overlay as PID 1 ----------
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
