# syntax=docker/dockerfile:1
# ============================================================
# hermes-web-ui —— Ekko Studio（UI + 网页聊天 agent）
# 基座 = hermes-base:main
#   → 工具链 / agent-browser / Chromium / 路径 与 hermes 容器完全一致，
#     不再各自安装（原先 webui 用上游基座，缺 agent-browser 导致 browser_exec 失败）
# ============================================================
ARG BASE_IMAGE=hermes-base:main
FROM ${BASE_IMAGE}

ARG NODE_VERSION=24.22.1

USER root

#RUN apt-get update && apt-get install -y --no-install-recommends \
#    ca-certificates \
#    curl \
#    ffmpeg \
#    make \
#    g++ \
#    && rm -rf /var/lib/apt/lists/*

#RUN ARCH=$(dpkg --print-architecture) \
#    && if [ "$ARCH" = "amd64" ]; then NODE_ARCH="x64"; else NODE_ARCH="$ARCH"; fi \
#    && echo "Downloading Node.js v${NODE_VERSION} for ${NODE_ARCH}" \
#    && curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz" \
#       -o /tmp/node.tar.gz \
#    && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
#       /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
#    && tar -xzf /tmp/node.tar.gz -C /usr/local --strip-components=1 \
#    && rm -f /tmp/node.tar.gz \
#    && node --version \
#    && npm --version

WORKDIR /app

COPY package*.json ./
# Increase Node.js memory limit to prevent OOM during build
ENV NODE_OPTIONS=--max-old-space-size=4096
RUN npm ci --ignore-scripts && npm rebuild node-pty

COPY . .

# ── 构建前置校验（2026-11-04）──────────────────────────────────────────────
# packages/client/src/utils/agent-catalog.ts 静态 import ../../../../config/agents.json。
# 该文件不属于上游 npm 包内容，从上游源码包同步时会缺失，构建期报
#   UNRESOLVED_IMPORT: Could not resolve '../../../../config/agents.json'
# 这里前置拦住并给出可执行的补救说明，避免跑到 vite 阶段才失败。
RUN set -e; \
    if [ ! -f /app/config/agents.json ]; then \
      echo "FATAL: /app/config/agents.json 缺失（agent 目录数据，非 npm 依赖）" >&2; \
      echo "  从现有镜像取回：docker cp hermes-webui:/app/config/agents.json app/config/" >&2; \
      exit 1; \
    fi; \
    echo "ok: config/agents.json $(wc -c < /app/config/agents.json) bytes"

# ── 本地补丁：注意力面板（2026-11-04 前只打在运行容器里，重建即丢）──────────
# patches/attention/ 是一次性补丁包：4 个新文件 + 幂等注册脚本。
# patch.py 对已应用的注册点会跳过，重复构建安全。
# 2026-11-18：此处改为「补丁丢失就在这一步报错」。
# 上游 0.8.28 起 app/.dockerignore 是白名单模式，漏放 '!patches/**' 会让 patches
# 根本不进构建上下文，补丁被静默跳过、拖到最后一步才报「缺少 AttentionView chunk」。
# 确有不需补丁的构建场景时显式传 --build-arg SKIP_ATTENTION_PATCH=1。
ARG SKIP_ATTENTION_PATCH=0
RUN set -e; \
    if [ "$SKIP_ATTENTION_PATCH" = "1" ]; then \
      echo "skip: 显式跳过注意力面板补丁 (SKIP_ATTENTION_PATCH=1)"; \
    else \
      test -f /app/patches/attention/patch.py \
        || { echo "FATAL: /app/patches/attention 未进入构建上下文" >&2; \
             echo "  常见原因：app/.dockerignore 为白名单模式，缺少 '!patches/**' 这一行。" >&2; exit 1; }; \
      cp -a /app/patches/attention/files/. /app/ && \
      python3 /app/patches/attention/patch.py; \
      test -f /app/packages/client/src/views/hermes/AttentionView.vue \
        || { echo "FATAL: 补丁视图未落到 packages/client/src/views/hermes/" >&2; exit 1; }; \
      grep -q 'hermes.attention' /app/packages/client/src/router/index.ts \
        || { echo "FATAL: 补丁未注册到 router/index.ts" >&2; exit 1; }; \
      echo "ok: 补丁已应用并注册" ; \
    fi

RUN npm run build && npm prune --omit=dev
RUN npm run verify:sharp-runtime

# ── 构建产物护栏（2026-11-04）──────────────────────────────────────────────
# 补丁丢失在历史上发生过两次（都表现为「镜像构建成功、功能却消失」）。
# 这里把「补丁必须在产物里」变成构建失败的硬条件，而不是靠人工去容器里 ls。
RUN set -e; \
    echo "-- 校验注意力面板已进入产物 --"; \
    test -n "$(ls /app/dist/client/assets/js 2>/dev/null | grep -i '^AttentionView-')" \
      || { echo "FATAL: dist 中缺少 AttentionView chunk" >&2; exit 1; }; \
    grep -q 'api/hermes/attention/panel' /app/dist/server/index.js \
      || { echo "FATAL: server 产物缺少 /api/hermes/attention/panel 路由" >&2; exit 1; }; \
    grep -q 'hermes.attention' /app/dist/client/assets/js/router-*.js \
      || { echo "FATAL: 客户端路由缺少 hermes.attention" >&2; exit 1; }; \
    echo "ok: 注意力面板产物校验通过"

ENV NODE_ENV=production
ENV HOME=/home/agent
ENV HERMES_HOME=/home/agent/.hermes
ENV HERMES_WEB_UI_MANAGED_GATEWAY=1
ENV STUDIO_P2P_UDP_PORT_RANGE=50000-50127
# Keep runtime-installed coding agent CLIs in the existing Studio data volume.
ENV NPM_CONFIG_PREFIX=/home/agent/.hermes-web-ui/coding-agent/npm
ENV PATH=/home/agent/.hermes-web-ui/coding-agent/npm/bin:/opt/hermes/.venv/bin:$PATH


# CRLF 归一 + 可执行位
RUN sed -i 's/\r$//' /app/bin/start-studio-all.sh && chmod +x /app/bin/start-studio-all.sh

EXPOSE 6060
EXPOSE 50000-50127/udp

ENTRYPOINT ["sh", "-c", "sed -i 's/\\r$//' /app/bin/*.sh 2>/dev/null; chmod +x /app/bin/*.sh 2>/dev/null; exec /app/bin/start-studio-all.sh"]
CMD []
