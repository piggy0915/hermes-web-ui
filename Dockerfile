# syntax=docker/dockerfile:1
# ============================================================
# hermes-web-ui —— Ekko Studio（UI + 网页聊天 agent）
# 基座 = hermes-base:main
#   → 工具链 / agent-browser / Chromium / 路径 与 hermes 容器完全一致，
#     不再各自安装（原先 webui 用上游基座，缺 agent-browser 导致 browser_exec 失败）
# ============================================================
ARG BASE_IMAGE=hermes-base:main
FROM ${BASE_IMAGE}

ARG NODE_VERSION=24.19.0

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

RUN npm run build && npm prune --omit=dev
RUN npm run verify:sharp-runtime

ENV NODE_ENV=production
ENV HOME=/home/agent
ENV HERMES_HOME=/home/agent/.hermes
ENV HERMES_WEB_UI_MANAGED_GATEWAY=1
# Keep runtime-installed coding agent CLIs in the existing Studio data volume.
ENV NPM_CONFIG_PREFIX=/home/agent/.hermes-web-ui/coding-agent/npm
ENV PATH=/home/agent/.hermes-web-ui/coding-agent/npm/bin:/opt/hermes/.venv/bin:$PATH


# CRLF 归一 + 可执行位
RUN sed -i 's/\r$//' /app/bin/start-studio-all.sh && chmod +x /app/bin/start-studio-all.sh

EXPOSE 6060

ENTRYPOINT ["sh", "-c", "sed -i 's/\\r$//' /app/bin/*.sh 2>/dev/null; chmod +x /app/bin/*.sh 2>/dev/null; exec /app/bin/start-studio-all.sh"]
CMD []
