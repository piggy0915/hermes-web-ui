#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把注意力面板接进 Ekko Studio（hermes-webui）的注册点。

幂等：已插入的段落不会重复插入。只改 5 处，改完由 apply.sh 触发编译。
运行环境：hermes-webui 容器内（/app 为工作目录）。
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


# 1) 服务端：注册路由 import + use
def patch_routes_ts(s: str) -> str:
    imp_anchor = "import { jobRoutes } from '../modules/hermes/routes/jobs'"
    imp_new = imp_anchor + "\r\nimport { attentionRoutes } from '../modules/hermes/routes/attention'"
    if "routes/attention'" not in s:
        assert imp_anchor in s, "routes.ts: import 锚点未命中"
        s = s.replace(imp_anchor, imp_new, 1)
    use_anchor = "  app.use(jobRoutes.routes())"
    use_new = use_anchor + "\r\n  app.use(attentionRoutes.routes())"
    if "app.use(attentionRoutes.routes())" not in s:
        assert use_anchor in s, "routes.ts: use 锚点未命中"
        s = s.replace(use_anchor, use_new, 1)
    return s


# 2) 服务端：模块出口
def patch_module_index(s: str) -> str:
    anchor = "export * from './routes/jobs'"
    if "routes/attention" in s:
        return s
    assert anchor in s, "modules/hermes/index.ts: 锚点未命中"
    return s.replace(anchor, anchor + "\r\nexport * from './routes/attention'", 1)


# 3) 客户端：路由
def patch_router(s: str) -> str:
    if "hermes.attention" in s:
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
        "      path: '/hermes/attention',\r\n"
        "      name: 'hermes.attention',\r\n"
        "      component: () => import('@/views/hermes/AttentionView.vue'),\r\n"
        "      meta: { hermesConfig: true },\r\n"
        "    },"
    )
    return s.replace(anchor, block, 1)


# 4) 客户端：侧边栏入口
def patch_sidebar(s: str) -> str:
    if "hermes.attention" in s:
        return s
    anchor = (
        '      <RouteLinkItem\r\n'
        '        class="hermes-config-nav-item"\r\n'
        '        :to="{ name: \'hermes.jobs\' }"'
    )
    assert anchor in s, "HermesConfigSidebar.vue: jobs 入口锚点未命中"
    item = (
        '      <RouteLinkItem\r\n'
        '        class="hermes-config-nav-item"\r\n'
        '        :to="{ name: \'hermes.attention\' }"\r\n'
        '        :active="activeRoute === \'hermes.attention\'"\r\n'
        '      >\r\n'
        '        <svg\r\n'
        '          width="17"\r\n'
        '          height="17"\r\n'
        '          viewBox="0 0 24 24"\r\n'
        '          fill="none"\r\n'
        '          stroke="currentColor"\r\n'
        '          stroke-width="1.7"\r\n'
        '          stroke-linecap="round"\r\n'
        '          stroke-linejoin="round"\r\n'
        '        >\r\n'
        '          <path d="M12 3a6 6 0 0 0-6 6v3.6L4.5 16h15L18 12.6V9a6 6 0 0 0-6-6Z" />\r\n'
        '          <path d="M9.5 19a2.5 2.5 0 0 0 5 0" />\r\n'
        '        </svg>\r\n'
        '        <span>{{ t("sidebar.attention") }}</span>\r\n'
        '      </RouteLinkItem>\r\n'
    )
    return s.replace(anchor, item + anchor, 1)


# 5) i18n：中文 / 英文
def make_i18n_patch(label_from: str, label_to: str):
    def _patch(s: str) -> str:
        if "sidebar.attention" in s or f"\n    attention: '{label_to}'," in s:
            return s
        anchor = f"    jobs: '{label_from}',"
        if anchor not in s:
            return s  # 该语言文件没有这个键，交给 i18n 回退
        return s.replace(anchor, anchor + f"\r\n    attention: '{label_to}',", 1)
    return _patch


TARGETS = [
    ("packages/server/src/bootstrap/routes.ts", patch_routes_ts),
    ("packages/server/src/modules/hermes/index.ts", patch_module_index),
    ("packages/client/src/router/index.ts", patch_router),
    ("packages/client/src/components/layout/HermesConfigSidebar.vue", patch_sidebar),
    ("packages/client/src/i18n/locales/zh.ts", make_i18n_patch("任务", "注意力")),
    ("packages/client/src/i18n/locales/en.ts", make_i18n_patch("Jobs", "Attention")),
]

if __name__ == "__main__":
    if not os.path.isdir(os.path.join(APP, "packages")):
        print("错误：/app/packages 不存在", file=sys.stderr)
        sys.exit(1)
    for path, fn in TARGETS:
        rw(path, fn)
    print(f"\n改动 {len(changed)} 个文件：{', '.join(changed) if changed else '无（均已应用）'}")
