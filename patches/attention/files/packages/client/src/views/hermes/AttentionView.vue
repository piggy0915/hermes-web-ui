<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { fetchAttentionPanel, type AttentionItem, type AttentionPanelResponse } from '@/api/hermes/attention'

/**
 * 注意力面板（只读）
 *
 * 遵守 Super-agent 005 的三条面板规则：
 *   1. 只列需要人的事——健康状态不占空间
 *   2. 计数恒等于它链接的列表长度（由后端 attention panel 保证，前端不做二次加工）
 *   3. 每条都给一条能直接执行的命令
 */
const data = ref<AttentionPanelResponse | null>(null)
const loading = ref(false)
const errorText = ref('')
const copied = ref('')

const needYou = computed<AttentionItem[]>(() => data.value?.需要你决定 ?? [])
const problems = computed<AttentionItem[]>(() => data.value?.系统问题 ?? [])
const total = computed(() => needYou.value.length + problems.value.length)
const isEmpty = computed(() => data.value !== null && total.value === 0)

async function load() {
  loading.value = true
  errorText.value = ''
  try {
    const res = await fetchAttentionPanel()
    data.value = res
    if (!res.ok) errorText.value = res.error || '面板数据读取失败'
  } catch (err) {
    errorText.value = String(err)
  } finally {
    loading.value = false
  }
}

async function copyCommand(cmd: string) {
  if (!cmd) return
  try {
    await navigator.clipboard.writeText(cmd)
    copied.value = cmd
    setTimeout(() => (copied.value = ''), 1500)
  } catch {
    copied.value = ''
  }
}

let timer: ReturnType<typeof setInterval> | undefined
onMounted(() => {
  load()
  timer = setInterval(load, 60_000)
})
onUnmounted(() => {
  if (timer) clearInterval(timer)
})
</script>

<template>
  <div class="attention-view">
    <header class="attention-head">
      <div>
        <h1>注意力面板</h1>
        <p class="sub">只读 · 只列需要你决定的事，健康状态不占空间</p>
      </div>
      <div class="head-actions">
        <span v-if="data?.generated_at" class="stamp">{{ data.generated_at.slice(11, 19) }}</span>
        <button class="btn" :disabled="loading" @click="load">
          {{ loading ? '刷新中…' : '刷新' }}
        </button>
      </div>
    </header>

    <p v-if="errorText" class="err">{{ errorText }}</p>

    <div v-if="isEmpty" class="empty">无事</div>

    <template v-else>
      <section v-if="needYou.length" class="block">
        <h2>需要你决定 <span class="count">{{ needYou.length }}</span></h2>
        <ul>
          <li v-for="item in needYou" :key="item.ref + item.what">
            <div class="row">
              <span class="what">{{ item.what }}</span>
              <code class="ref">{{ item.ref }}</code>
            </div>
            <p v-if="item.detail" class="detail">{{ item.detail }}</p>
            <div v-if="item.action" class="cmd">
              <code>{{ item.action }}</code>
              <button class="copy" @click="copyCommand(item.action)">
                {{ copied === item.action ? '已复制' : '复制' }}
              </button>
            </div>
          </li>
        </ul>
      </section>

      <section v-if="problems.length" class="block warn">
        <h2>系统问题 <span class="count">{{ problems.length }}</span></h2>
        <ul>
          <li v-for="item in problems" :key="item.ref + item.what">
            <div class="row">
              <span class="what">{{ item.what }}</span>
              <code class="ref">{{ item.ref }}</code>
            </div>
            <p v-if="item.detail" class="detail">{{ item.detail }}</p>
            <div v-if="item.action" class="cmd">
              <code>{{ item.action }}</code>
              <button class="copy" @click="copyCommand(item.action)">
                {{ copied === item.action ? '已复制' : '复制' }}
              </button>
            </div>
          </li>
        </ul>
      </section>
    </template>

    <footer v-if="data?.计数" class="foot">
      计数自校验：{{ Object.entries(data.计数).map(([k, v]) => `${k} ${v}`).join(' · ') }}
    </footer>
  </div>
</template>

<style scoped>
.attention-view {
  padding: 24px 28px;
  max-width: 880px;
  color: var(--text-primary, #e6e6e6);
}
.attention-head {
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
.head-actions {
  display: flex;
  align-items: center;
  gap: 10px;
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
.empty {
  padding: 28px 0;
  font-size: 13px;
  opacity: 0.45;
}
.block {
  border: 1px solid var(--border-color, #2a2a2a);
  border-radius: 8px;
  padding: 14px 16px;
  margin-bottom: 14px;
}
.block.warn {
  border-color: #6b4b1f;
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
ul {
  list-style: none;
  margin: 0;
  padding: 0;
}
li {
  padding: 8px 0;
  border-top: 1px solid var(--border-color, #232323);
}
li:first-child {
  border-top: none;
  padding-top: 0;
}
.row {
  display: flex;
  align-items: center;
  gap: 8px;
}
.what {
  font-size: 13px;
}
.ref {
  font-size: 11px;
  opacity: 0.55;
}
.detail {
  margin: 4px 0 0;
  font-size: 12px;
  opacity: 0.7;
  line-height: 1.5;
}
.cmd {
  margin-top: 6px;
  display: flex;
  align-items: center;
  gap: 8px;
}
.cmd code {
  font-size: 11px;
  background: rgba(255, 255, 255, 0.05);
  border-radius: 4px;
  padding: 2px 6px;
}
.copy {
  border: none;
  background: transparent;
  color: inherit;
  opacity: 0.5;
  font-size: 11px;
  cursor: pointer;
}
.copy:hover {
  opacity: 0.9;
}
.err {
  color: #e0776b;
  font-size: 12px;
}
.foot {
  margin-top: 6px;
  font-size: 11px;
  opacity: 0.35;
}
</style>
