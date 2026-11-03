import type { Context } from 'koa'
import { execFile } from 'child_process'

/**
 * 注意力账本只读接口。
 *
 * 数据源是 Hermes 容器里的 `attention panel --json`（/opt/data 为共享卷，webui 也看得到）。
 * 这里只做读取与转发，不写任何状态——面板的诚实性由 attention.py 的 selftest 保证。
 */
const ATTENTION_CLI = process.env.ATTENTION_CLI || '/opt/data/attention/attention.py'
const PYTHON = process.env.ATTENTION_PYTHON || 'python3'
const TIMEOUT_MS = 8000

interface PanelResult {
  ok: boolean
  error?: string
  [key: string]: unknown
}

function runPanel(): Promise<PanelResult> {
  return new Promise(resolve => {
    execFile(
      PYTHON,
      [ATTENTION_CLI, 'panel', '--json'],
      { timeout: TIMEOUT_MS, maxBuffer: 2 * 1024 * 1024 },
      (err, stdout) => {
        if (err) {
          resolve({ ok: false, error: String(err.message || err) })
          return
        }
        try {
          resolve({ ok: true, ...(JSON.parse(stdout) as Record<string, unknown>) })
        } catch (parseError) {
          resolve({ ok: false, error: `parse error: ${String(parseError)}` })
        }
      },
    )
  })
}

export async function panel(ctx: Context): Promise<void> {
  const data = await runPanel()
  ctx.status = 200
  ctx.body = {
    generated_at: new Date().toISOString(),
    ...data,
  }
}
