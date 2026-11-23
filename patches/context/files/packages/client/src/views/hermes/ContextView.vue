<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import {
  fetchContextOverview,
  fetchContextSession,
  type ContextOverview,
  type ContextSessionDetail,
} from '@/api/hermes/context'

/**
 * 上下文洞察（只读）
 *
 * 对照 DeepSeek Harness 的 dsh-context 插件，落在 Hermes 自己的数据上：
 *   - KPI 栏：Token / 成本 / 缓存命中 / API 调用
 *   - 按日柱状：最近 N 天的 input/output
 *   - 会话卡片：一键下钻到单会话上下文拆分
 *   - 单会话：系统提示词 / 用户 / 助手 / 工具结果 四段占比 + 工具分布 + 子 Agent
 *
 * 数据源为 Hermes state.db（只读），所有数字来自实测列，不估算金额。
 */

const days = ref(30)
const data = ref<ContextOverview | null>(null)
const loading = ref(false)
const errorText = ref('')

const detail = ref<ContextSessionDetail | null>(null)
const detailLoading = ref(false)
const selectedId = ref('')

const kpi = computed(() => data.value?.kpi ?? null)
const cards = computed(() => data.value?.sessions ?? [])
const daily = computed(() => data.value?.daily ?? [])
const byModel = computed(() => data.value?.by_model ?? [])
const maxDaily = computed(() => {
  const m = Math.max(...daily.value.map(d => d.input_tokens + d.output_tokens), 1)
  return m
})

function fmt(n: number | null | undefined): string {
  const v = Number(n || 0)
  if (v >= 1_000_000) return (v / 1_000_000).toFixed(2) + 'M'
  if (v >= 1_000) return (v / 1_000).toFixed(1) + 'k'
  return String(v)
}

function money(n: number | null | undefined): string {
  return '$' + Number(n || 0).toFixed(4)
}

function pct(n: number | null | undefined): string {
  return (Number(n || 0) * 100).toFixed(1) + '%'
}

async function load() {
  loading.value = true
  errorText.value = ''
  try {
    const res = await fetchContextOverview(days.value)
    data.value = res
    if (!res.ok) errorText.value = res.error || '上下文数据读取失败'
  } catch (err) {
    errorText.value = String(err)
  } finally {
    loading.value = false
  }
}

async function openSession(id: string) {
  selectedId.value = id
  detailLoading.value = true
  detail.value = null
  try {
    detail.value = await fetchContextSession(id)
  } catch (err) {
    errorText.value = String(err)
  } finally {
    detailLoading.value = false
  }
}

function closeDetail() {
  selectedId.value = ''
  detail.value = null
}

const compColors: Record<string, string> = {
  system: '#6b7fd7',
  user: '#4f9d69',
  assistant: '#c9a227',
  tool: '#b3654f',
}

const compTotal = computed(() => detail.value?.composition_total || 0)

function compWidth(tokens: number): string {
  if (!compTotal.value) return '0%'
  return ((tokens / compTotal.value) * 100).toFixed(1) + '%'
}

let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  load()
  timer = setInterval(load, 120_000)
})
onUnmounted(() => {
  if (timer) clearInterval(timer)
})
</script>

<template>
  <div class="context-view">
    <header class="ctx-head">
      <div>
        <h1>上下文洞察</h1>
        <p class="sub">只读 · Token 组成、成本与缓存命中，来自 Hermes state.db 实测</p>
      </div>
      <div class="head-actions">
        <div class="range">
          <button
            v-for="d in [1, 7, 30, 90]"
            :key="d"
            class="chip"
            :class="{ on: days === d }"
            @click="days = d; load()"
          >
            {{ d === 1 ? '今天' : d + ' 天' }}
          </button>
        </div>
        <span v-if="data?.generated_at" class="stamp">{{ data.generated_at.slice(11, 19) }}</span>
        <button class="btn" :disabled="loading" @click="load">
          {{ loading ? '刷新中…' : '刷新' }}
        </button>
      </div>
    </header>

    <p v-if="errorText" class="err">{{ errorText }}</p>

    <section v-if="kpi" class="kpi-row">
      <div class="kpi">
        <span class="k-label">会话</span>
        <span class="k-value">{{ kpi.sessions }}</span>
      </div>
      <div class="kpi">
        <span class="k-label">API 调用</span>
        <span class="k-value">{{ fmt(kpi.api_calls) }}</span>
      </div>
      <div class="kpi">
        <span class="k-label">输入 Token</span>
        <span class="k-value">{{ fmt(kpi.input_tokens) }}</span>
      </div>
      <div class="kpi">
        <span class="k-label">输出 Token</span>
        <span class="k-value">{{ fmt(kpi.output_tokens) }}</span>
      </div>
      <div class="kpi">
        <span class="k-label">缓存读</span>
        <span class="k-value">{{ fmt(kpi.cache_read_tokens) }}</span>
      </div>
      <div class="kpi">
        <span class="k-label">缓存命中</span>
        <span class="k-value">{{ pct(kpi.cache_hit_rate) }}</span>
      </div>
      <div class="kpi">
        <span class="k-label">估算成本</span>
        <span class="k-value">{{ money(kpi.estimated_cost_usd) }}</span>
      </div>
    </section>

    <section v-if="daily.length" class="block">
      <h2>每日用量 <span class="count">{{ daily.length }} 天</span></h2>
      <div class="bars">
        <div v-for="d in daily" :key="d.date" class="bar-col" :title="`${d.date}  输入 ${fmt(d.input_tokens)} / 输出 ${fmt(d.output_tokens)} · ${d.sessions} 会话`">
          <div class="bar-stack">
            <div class="bar out" :style="{ height: ((d.output_tokens / maxDaily) * 100) + '%' }"></div>
            <div class="bar in" :style="{ height: ((d.input_tokens / maxDaily) * 100) + '%' }"></div>
          </div>
          <span class="bar-label">{{ d.date.slice(5) }}</span>
        </div>
      </div>
      <p class="legend"><span class="dot in"></span>输入 <span class="dot out"></span>输出</p>
    </section>

    <section v-if="byModel.length" class="block">
      <h2>按模型 <span class="count">{{ byModel.length }}</span></h2>
      <table class="tbl">
        <thead>
          <tr><th>模型</th><th>会话</th><th>输入</th><th>输出</th><th>缓存读</th><th>成本</th></tr>
        </thead>
        <tbody>
          <tr v-for="m in byModel" :key="m.model">
            <td class="mono">{{ m.model }}</td>
            <td>{{ m.sessions }}</td>
            <td>{{ fmt(m.input_tokens) }}</td>
            <td>{{ fmt(m.output_tokens) }}</td>
            <td>{{ fmt(m.cache_read_tokens) }}</td>
            <td>{{ money(m.cost_usd) }}</td>
          </tr>
        </tbody>
      </table>
    </section>

    <section class="block">
      <h2>会话 <span class="count">{{ cards.length }}</span></h2>
      <p v-if="!cards.length" class="empty">该时间范围内没有会话</p>
      <ul v-else class="sess-list">
        <li v-for="s in cards" :key="s.id" class="sess" @click="openSession(s.id)">
          <div class="sess-main">
            <div class="row">
              <span class="title">{{ s.title }}</span>
              <span v-if="s.is_child" class="tag">子 Agent</span>
            </div>
            <div class="meta">
              <span class="mono">{{ s.model }}</span>
              <span>·</span>
              <span>{{ s.messages }} 消息 / {{ s.tool_calls }} 工具 / {{ s.api_calls }} 调用</span>
              <span>·</span>
              <span>{{ (s.last_activity_at || s.started_at || '').slice(0, 16).replace('T', ' ') }}</span>
            </div>
          </div>
          <div class="sess-nums">
            <span>{{ fmt(s.input_tokens) }} in</span>
            <span>{{ fmt(s.cache_read_tokens) }} cache</span>
            <span>{{ money(s.cost_usd) }}</span>
          </div>
        </li>
      </ul>
    </section>

    <div v-if="selectedId" class="drawer-mask" @click.self="closeDetail">
      <div class="drawer">
        <header class="drawer-head">
          <div>
            <h2>{{ detail?.session?.title || '会话详情' }}</h2>
            <p class="sub mono">{{ selectedId }}</p>
          </div>
          <button class="btn" @click="closeDetail">关闭</button>
        </header>

        <p v-if="detailLoading" class="empty">读取中…</p>
        <p v-else-if="detail && !detail.ok" class="err">{{ detail.error }}</p>

        <template v-if="detail && detail.ok">
          <section class="block">
            <h2>上下文组成 <span class="count">≈ {{ fmt(compTotal) }} tokens</span></h2>
            <div class="stackbar">
              <div
                v-for="p in detail.composition"
                :key="p.key"
                class="seg"
                :style="{ width: compWidth(p.tokens), background: compColors[p.key] }"
                :title="`${p.label} ${fmt(p.tokens)}`"
              ></div>
            </div>
            <ul class="comp-legend">
              <li v-for="p in detail.composition" :key="p.key">
                <span class="dot" :style="{ background: compColors[p.key] }"></span>
                {{ p.label }}
                <b>{{ fmt(p.tokens) }}</b>
                <span class="dim">{{ compWidth(p.tokens) }}</span>
              </li>
            </ul>
            <p class="foot">{{ detail.estimate_note }}</p>
          </section>

          <section class="block">
            <h2>会话统计</h2>
            <div class="grid">
              <div><span class="k-label">模型</span><span class="mono">{{ detail.session.model }}</span></div>
              <div><span class="k-label">输入</span><span>{{ fmt(detail.session.input_tokens) }}</span></div>
              <div><span class="k-label">输出</span><span>{{ fmt(detail.session.output_tokens) }}</span></div>
              <div><span class="k-label">缓存读</span><span>{{ fmt(detail.session.cache_read_tokens) }}</span></div>
              <div><span class="k-label">reasoning</span><span>{{ fmt(detail.session.reasoning_tokens) }}</span></div>
              <div><span class="k-label">成本</span><span>{{ money(detail.session.cost_usd) }}</span></div>
              <div><span class="k-label">消息</span><span>{{ detail.session.messages }}</span></div>
              <div><span class="k-label">工具调用</span><span>{{ detail.session.tool_calls }}</span></div>
              <div><span class="k-label">API 调用</span><span>{{ detail.session.api_calls }}</span></div>
              <div><span class="k-label">成本状态</span><span>{{ detail.session.cost_status || '—' }}</span></div>
            </div>
          </section>

          <section v-if="detail.tools.length" class="block">
            <h2>工具分布 <span class="count">{{ detail.tools.length }}</span></h2>
            <table class="tbl">
              <thead><tr><th>工具</th><th>次数</th><th>结果字符</th></tr></thead>
              <tbody>
                <tr v-for="t in detail.tools" :key="t.tool_name">
                  <td class="mono">{{ t.tool_name }}</td>
                  <td>{{ t.n }}</td>
                  <td>{{ fmt(t.chars) }}</td>
                </tr>
              </tbody>
            </table>
          </section>

          <section v-if="detail.model_usage.length" class="block">
            <h2>按模型/任务拆分 <span class="count">{{ detail.model_usage.length }}</span></h2>
            <table class="tbl">
              <thead><tr><th>模型</th><th>任务</th><th>调用</th><th>输入</th><th>输出</th><th>缓存读</th><th>成本</th></tr></thead>
              <tbody>
                <tr v-for="(m, i) in detail.model_usage" :key="i">
                  <td class="mono">{{ m.model }}</td>
                  <td>{{ m.task || '—' }}</td>
                  <td>{{ m.api_call_count }}</td>
                  <td>{{ fmt(m.input_tokens) }}</td>
                  <td>{{ fmt(m.output_tokens) }}</td>
                  <td>{{ fmt(m.cache_read_tokens) }}</td>
                  <td>{{ money(m.cost) }}</td>
                </tr>
              </tbody>
            </table>
          </section>

          <section v-if="detail.children.length" class="block">
            <h2>子 Agent <span class="count">{{ detail.children.length }}</span></h2>
            <ul class="sess-list">
              <li v-for="c in detail.children" :key="c.id" class="sess" @click="openSession(c.id)">
                <div class="sess-main">
                  <span class="title">{{ c.title || c.id.slice(0, 12) + '…' }}</span>
                  <div class="meta">
                    <span class="mono">{{ c.model }}</span>
                    <span>·</span>
                    <span>{{ c.message_count }} 消息</span>
                  </div>
                </div>
                <div class="sess-nums">
                  <span>{{ fmt(c.input_tokens) }} in</span>
                </div>
              </li>
            </ul>
          </section>
        </template>
      </div>
    </div>
  </div>
</template>

<style scoped>
.context-view {
  padding: 24px 28px;
  max-width: 1080px;
  color: var(--text-primary, #e6e6e6);
}
.ctx-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 20px;
}
h1 {
  font-size: 18px;
  margin: 0 0 4px;
}
.sub {
  margin: 0;
  font-size: 12px;
  opacity: 0.55;
}
.mono {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 12px;
}
.head-actions {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}
.range {
  display: flex;
  gap: 4px;
}
.chip {
  border: 1px solid var(--border-color, #333);
  background: transparent;
  color: inherit;
  border-radius: 999px;
  padding: 3px 10px;
  font-size: 11px;
  cursor: pointer;
  opacity: 0.6;
}
.chip.on {
  opacity: 1;
  border-color: var(--text-primary, #e6e6e6);
}
.stamp {
  font-size: 11px;
  opacity: 0.45;
  font-variant-numeric: tabular-nums;
}
.btn {
  border: 1px solid var(--border-color, #333);
  background: transparent;
  color: inherit;
  border-radius: 6px;
  padding: 5px 12px;
  font-size: 12px;
  cursor: pointer;
}
.btn:disabled {
  opacity: 0.5;
  cursor: default;
}
.kpi-row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
  gap: 10px;
  margin-bottom: 16px;
}
.kpi {
  border: 1px solid var(--border-color, #2a2a2a);
  border-radius: 8px;
  padding: 10px 12px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.k-label {
  font-size: 11px;
  opacity: 0.5;
  display: block;
}
.k-value {
  font-size: 17px;
  font-variant-numeric: tabular-nums;
}
.block {
  border: 1px solid var(--border-color, #2a2a2a);
  border-radius: 8px;
  padding: 14px 16px;
  margin-bottom: 14px;
}
h2 {
  font-size: 13px;
  margin: 0 0 10px;
  display: flex;
  align-items: center;
  gap: 8px;
}
.count {
  font-size: 11px;
  opacity: 0.7;
  background: rgba(255, 255, 255, 0.08);
  border-radius: 10px;
  padding: 1px 8px;
}
.bars {
  display: flex;
  align-items: flex-end;
  gap: 3px;
  height: 120px;
  overflow-x: auto;
}
.bar-col {
  flex: 1 0 8px;
  min-width: 8px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  height: 100%;
}
.bar-stack {
  flex: 1;
  width: 100%;
  display: flex;
  flex-direction: column;
  justify-content: flex-end;
  gap: 1px;
}
.bar {
  border-radius: 2px 2px 0 0;
}
.bar.in {
  background: #5b8ec9;
}
.bar.out {
  background: #c9a227;
}
.bar-label {
  font-size: 9px;
  opacity: 0.4;
  writing-mode: vertical-rl;
  height: 30px;
}
.legend {
  margin: 8px 0 0;
  font-size: 11px;
  opacity: 0.6;
}
.dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  margin-right: 4px;
}
.dot.in { background: #5b8ec9; }
.dot.out { background: #c9a227; }
.tbl {
  width: 100%;
  border-collapse: collapse;
  font-size: 12px;
}
.tbl th {
  text-align: left;
  font-weight: 500;
  opacity: 0.5;
  padding: 4px 8px 6px 0;
  border-bottom: 1px solid var(--border-color, #2a2a2a);
}
.tbl td {
  padding: 5px 8px 5px 0;
  border-bottom: 1px solid var(--border-color, #1f1f1f);
  font-variant-numeric: tabular-nums;
}
.sess-list {
  list-style: none;
  margin: 0;
  padding: 0;
}
.sess {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 9px 0;
  border-top: 1px solid var(--border-color, #232323);
  cursor: pointer;
}
.sess:first-child {
  border-top: none;
}
.sess:hover {
  background: rgba(255, 255, 255, 0.03);
}
.sess-main {
  min-width: 0;
}
.row {
  display: flex;
  align-items: center;
  gap: 8px;
}
.title {
  font-size: 13px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 520px;
}
.tag {
  font-size: 10px;
  border: 1px solid var(--border-color, #444);
  border-radius: 8px;
  padding: 0 6px;
  opacity: 0.7;
}
.meta {
  display: flex;
  gap: 6px;
  font-size: 11px;
  opacity: 0.5;
  margin-top: 3px;
  flex-wrap: wrap;
}
.sess-nums {
  display: flex;
  gap: 12px;
  font-size: 11px;
  opacity: 0.7;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}
.empty {
  padding: 20px 0;
  font-size: 13px;
  opacity: 0.45;
}
.err {
  color: #e0776b;
  font-size: 12px;
}
.foot {
  margin: 8px 0 0;
  font-size: 11px;
  opacity: 0.35;
}
.drawer-mask {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.55);
  display: flex;
  justify-content: flex-end;
  z-index: 60;
}
.drawer {
  width: min(760px, 92vw);
  height: 100%;
  overflow-y: auto;
  background: var(--bg-primary, #17171a);
  border-left: 1px solid var(--border-color, #2a2a2a);
  padding: 20px 22px;
}
.drawer-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 14px;
}
.stackbar {
  display: flex;
  height: 22px;
  border-radius: 5px;
  overflow: hidden;
  background: rgba(255, 255, 255, 0.05);
}
.seg {
  height: 100%;
}
.comp-legend {
  list-style: none;
  margin: 10px 0 0;
  padding: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 14px;
  font-size: 12px;
}
.comp-legend b {
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  margin-left: 4px;
}
.dim {
  opacity: 0.45;
  margin-left: 4px;
}
.grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 10px;
  font-size: 12px;
}
.grid > div {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
</style>
