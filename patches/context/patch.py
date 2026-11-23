#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把上下文洞察面板接进 Ekko Studio（hermes-webui）的注册点。

与 patches/attention/patch.py 同构：4 个新文件 + 幂等注册脚本，改 6 处注册点。
锚点取基座源码（jobs）而非 attention，因为 attention 同样是构建期补丁、
宿主源码树里并不存在，而 patches 必须对任何构建顺序都幂等。

幂等：已插入的段落不会重复插入。
运行环境：hermes-webui 容器内（/app 为工作目录），由 Dockerfile 在 build 阶段调用。
"""
import io
import os
import sys

APP = os.environ.get("APP_ROOT", "/app")
changed = []


def rw(path, fn):
    full = os.path.join(APP, path)
    raw = io.open(full, encoding="utf-8", newline="").read()
    out = fn(raw)
    if out == raw:
        print(f"  [skip] {path}")
        return
    io.open(full, "w", encoding="utf-8", newline="").write(out)
    changed.append(path)
    print(f"  [edit] {path}")


def insert_after(s: str, anchor: str, block: str) -> str:
    """幂等插入：命中 anchor 后追加 block，已存在则跳过。"""
    return s


# 1) 服务端：注册路由 import + use（锚点：jobs）
def patch_routes_ts(s: str) -> str:
    imp_anchor = "import { jobRoutes } from '../modules/hermes/routes/jobs'"
    imp_new = imp_anchor + "\r\nimport { contextRoutes } from '../modules/hermes/routes/context'"
    if "routes/context'" not in s:
        assert imp_anchor in s, "routes.ts: jobs import 锚点未命中"
        s = s.replace(imp_anchor, imp_new, 1)
    use_anchor = "  app.use(jobRoutes.routes())"
    use_new = use_anchor + "\r\n  app.use(contextRoutes.routes())"
    if "app.use(contextRoutes.routes())" not in s:
        assert use_anchor in s, "routes.ts: jobs use 锚点未命中"
        s = s.replace(use_anchor, use_new, 1)
    return s


# 2) 服务端：模块出口
def patch_module_index(s: str) -> str:
    anchor = "export * from './routes/jobs'"
    if "routes/context" in s:
        return s
    assert anchor in s, "modules/hermes/index.ts: jobs 出口锚点未命中"
    return s.replace(anchor, anchor + "\r\nexport * from './routes/context'", 1)


# 3) 客户端：路由（锚点：jobs 路由块）
def patch_router(s: str) -> str:
    if "hermes.context" in s:
        return s
    anchor = (
        "    {\r\n"
        "      path: '/hermes/jobs',\r\n"
        "      name: 'hermes.jobs',\r\n"
        "      component: () => import('@/views/hermes/JobsView.vue'),\r\n"
        "      meta: { hermesConfig: true },\r\n"
        "    },"
    )
    assert anchor in s, "router/index.ts: jobs 路由锚点未命中"
    block = (
        anchor
        + "\r\n    {\r\n"
        "      path: '/hermes/context',\r\n"
        "      name: 'hermes.context',\r\n"
        "      component: () => import('@/views/hermes/ContextView.vue'),\r\n"
        "      meta: { hermesConfig: true },\r\n"
        "    },"
    )
    return s.replace(anchor, block, 1)


# 4) 客户端：侧边栏入口（紧跟 jobs 入口之后）
def patch_sidebar(s: str) -> str:
    if "hermes.context" in s:
        return s
    anchor = (
        '      <RouteLinkItem\r\n'
        '        class="hermes-config-nav-item"\r\n'
        "        :to=\"{ name: 'hermes.jobs' }\"\r\n"
        '        :active="activeRoute === \'hermes.jobs\'"\r\n'
        "      >\r\n"
        "        <svg\r\n"
        '          width="17"\r\n'
        '          height="17"\r\n'
        '          viewBox="0 0 24 24"\r\n'
        '          fill="none"\r\n'
        '          stroke="currentColor"\r\n'
        '          stroke-width="1.7"\r\n'
        '          stroke-linecap="round"\r\n'
        '          stroke-linejoin="round"\r\n'
        "        >\r\n"
        '          <rect x="3" y="4" width="18" height="18" rx="2" />\r\n'
        '          <path d="M16 2v4M8 2v4M3 10h18" />\r\n'
        "        </svg>\r\n"
        '        <span>{{ t("sidebar.jobs") }}</span>\r\n'
        "      </RouteLinkItem>\r\n"
    )
    assert anchor in s, "HermesConfigSidebar.vue: jobs 入口锚点未命中"
    item = (
        '      <RouteLinkItem\r\n'
        '        class="hermes-config-nav-item"\r\n'
        "        :to=\"{ name: 'hermes.context' }\"\r\n"
        '        :active="activeRoute === \'hermes.context\'"\r\n'
        "      >\r\n"
        "        <svg\r\n"
        '          width="17"\r\n'
        '          height="17"\r\n'
        '          viewBox="0 0 24 24"\r\n'
        '          fill="none"\r\n'
        '          stroke="currentColor"\r\n'
        '          stroke-width="1.7"\r\n'
        '          stroke-linecap="round"\r\n'
        '          stroke-linejoin="round"\r\n'
        "        >\r\n"
        '          <rect x="3" y="4" width="18" height="16" rx="2" />\r\n'
        '          <path d="M7 9h10M7 13h6" />\r\n'
        "        </svg>\r\n"
        '        <span>{{ t("sidebar.context") }}</span>\r\n'
        "      </RouteLinkItem>\r\n"
    )
    return s.replace(anchor, anchor + item, 1)


# 5) i18n：中文 / 英文
def make_i18n_patch(jobs_label: str, context_label: str):
    def _patch(s: str) -> str:
        if "sidebar.context" in s or f"\n    context: '{context_label}'," in s:
            return s
        anchor = f"    jobs: '{jobs_label}',"
        if anchor not in s:
            return s  # 该语言文件没有这个键，交给 i18n 回退
        return s.replace(anchor, anchor + f"\r\n    context: '{context_label}',", 1)
    return _patch


TARGETS = [
    ("packages/server/src/bootstrap/routes.ts", patch_routes_ts),
    ("packages/server/src/modules/hermes/index.ts", patch_module_index),
    ("packages/client/src/router/index.ts", patch_router),
    ("packages/client/src/components/layout/HermesConfigSidebar.vue", patch_sidebar),
    ("packages/client/src/i18n/locales/zh.ts", make_i18n_patch("任务", "上下文")),
    ("packages/client/src/i18n/locales/en.ts", make_i18n_patch("Jobs", "Context")),
]

if __name__ == "__main__":
    if not os.path.isdir(os.path.join(APP, "packages")):
        print("错误：/app/packages 不存在", file=sys.stderr)
        sys.exit(1)
    for path, fn in TARGETS:
        rw(path, fn)
    print(f"\n改动 {len(changed)} 个文件：{', '.join(changed) if changed else '无（均已应用）'}")
