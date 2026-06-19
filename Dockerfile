ARG BASE_IMAGE=nousresearch/hermes-agent:v2026.6.5
FROM ${BASE_IMAGE}

ARG NODE_VERSION=24.15.0

USER root

# 更换为国内APT源（清华源）
RUN sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list.d/debian.sources 2>/dev/null || \
    sed -i 's/deb.debian.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    ffmpeg \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# 使用国内镜像下载Node.js（使用华为云镜像）
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "amd64" ]; then NODE_ARCH="x64"; else NODE_ARCH="$ARCH"; fi \
    && echo "Downloading Node.js v${NODE_VERSION} for ${NODE_ARCH}" \
    && curl -fsSL "https://mirrors.huaweicloud.com/nodejs/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz" \
       -o /tmp/node.tar.gz \
    || curl -fsSL "https://registry.npmmirror.com/-/binary/node/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.gz" \
       -o /tmp/node.tar.gz \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
       /usr/local/bin/node /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
    && tar -xzf /tmp/node.tar.gz -C /usr/local --strip-components=1 \
    && rm -f /tmp/node.tar.gz \
    && node --version \
    && npm --version

WORKDIR /app

COPY package*.json ./
# Increase Node.js memory limit to prevent OOM during build
ENV NODE_OPTIONS=--max-old-space-size=4096

# 设置环境变量让node-gyp和npm使用国内镜像（所有配置通过环境变量）
ENV NPM_CONFIG_REGISTRY=https://registry.npmmirror.com
ENV NODEJS_ORG_MIRROR=https://registry.npmmirror.com/-/binary/node
ENV ELECTRON_MIRROR=https://registry.npmmirror.com/-/binary/electron/
ENV PYTHON_MIRROR=https://registry.npmmirror.com/-/binary/python/
RUN npm config set registry https://registry.npmmirror.com && \
    npm ci --ignore-scripts && \
    npm rebuild node-pty
#RUN npm ci --ignore-scripts && npm rebuild node-pty

COPY . .

RUN npm run build && npm prune --omit=dev

ENV NODE_ENV=production
ENV HOME=/home/agent
ENV HERMES_HOME=/home/agent/.hermes
ENV HERMES_WEB_UI_MANAGED_GATEWAY=1
ENV PATH=/opt/hermes/.venv/bin:$PATH

EXPOSE 6060

# 强制覆盖基础镜像的默认启动脚本，让镜像本身具备独立运行的能力
ENTRYPOINT ["node", "dist/server/index.js"]
CMD []
