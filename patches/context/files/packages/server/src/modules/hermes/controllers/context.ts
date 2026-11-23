import type { Context as KoaContext } from 'koa'

type Ctx = KoaContext & { params?: Record<string, string | undefined> }
import { execFile } from 'child_process'

/**
 * Hermes 上下文洞察只读接口（对照 dsh-context 的 Context Insights / Context 页）。
 *
 * 数据源：Hermes 容器的 state.db（webui 通过 /home/agent/.hermes-rt/state.db 只读打开）。
 * 只读、不改任何状态；金额与 token 全部来自 sessions / session_model_usage 实测列。
 */
const STATE_DB = process.env.HERMES_STATE_DB || '/home/agent/.hermes-rt/state.db'
const PYTHON = process.env.CONTEXT_PYTHON || 'python3'
const TIMEOUT_MS = 10000

const SCRIPT = String.raw`
import json, sqlite3, sys, math
from datetime import datetime, timedelta, timezone

db_path, mode, arg1, arg2 = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
days = int(arg1 or 30) if arg1 else 30
sid = arg2 or ''

con = sqlite3.connect('file:%s?mode=ro' % db_path, uri=True)
con.row_factory = sqlite3.Row

def q(sql, params=()):
    return [dict(r) for r in con.execute(sql, params)]

def iso(ts):
    if not ts: return None
    try:
        return datetime.fromtimestamp(float(ts), timezone.utc).astimezone().isoformat(timespec='seconds')
    except Exception:
        return None

out = {'ok': True, 'generated_at': datetime.now(timezone.utc).astimezone().isoformat(timespec='seconds')}

if mode == 'overview':
    since = float(arg1) if arg1 else (datetime.now() - timedelta(days=30)).timestamp()
    # 窗口内会话（started_at / last_activity_at 为 REAL 类型，必须数字比较）
    sess = q("""select id, model, message_count, tool_call_count, input_tokens, output_tokens,
      cache_read_tokens, cache_write_tokens, reasoning_tokens, api_call_count,
      estimated_cost_usd, cost_status, started_at, last_activity_at, title,
      parent_session_id, profile_name, cwd
      from sessions where coalesce(last_activity_at, started_at) >= ?
      order by coalesce(last_activity_at, started_at) desc""", (since,))

    def num(v):
        return float(v) if v is not None else 0.0

    tot_in = sum(num(s['input_tokens']) for s in sess)
    tot_out = sum(num(s['output_tokens']) for s in sess)
    tot_cache = sum(num(s['cache_read_tokens']) for s in sess)
    tot_cw = sum(num(s['cache_write_tokens']) for s in sess)
    tot_reason = sum(num(s['reasoning_tokens']) for s in sess)
    tot_cost = sum(num(s['estimated_cost_usd']) for s in sess)
    calls = sum(int(s['api_call_count'] or 0) for s in sess)
    priced = sum(1 for s in sess if s['cost_status'] not in (None, 'unknown'))
    denom = tot_in + tot_cache
    hit = (tot_cache / denom) if denom else 0.0

    out['kpi'] = {
        'sessions': len(sess),
        'api_calls': calls,
        'input_tokens': int(tot_in),
        'output_tokens': int(tot_out),
        'cache_read_tokens': int(tot_cache),
        'cache_write_tokens': int(tot_cw),
        'reasoning_tokens': int(tot_reason),
        'total_tokens': int(tot_in + tot_out + tot_cache),
        'estimated_cost_usd': round(tot_cost, 4),
        'cache_hit_rate': round(hit, 4),
        'cost_coverage': {'priced': priced, 'unknown': len(sess) - priced},
    }

    # 按日（最近 N 天，含空日）
    daily = {}
    for s in sess:
        ts = s['last_activity_at'] or s['started_at']
        try:
            d = datetime.fromtimestamp(float(ts)).strftime('%Y-%m-%d')
        except Exception:
            continue
        b = daily.setdefault(d, {'date': d, 'input_tokens': 0, 'output_tokens': 0,
                                 'cache_read_tokens': 0, 'cost_usd': 0.0, 'sessions': 0})
        b['input_tokens'] += int(num(s['input_tokens']))
        b['output_tokens'] += int(num(s['output_tokens']))
        b['cache_read_tokens'] += int(num(s['cache_read_tokens']))
        b['cost_usd'] = round(b['cost_usd'] + num(s['estimated_cost_usd']), 4)
        b['sessions'] += 1
    today = datetime.now()
    for i in range(days):
        d = (today - timedelta(days=i)).strftime('%Y-%m-%d')
        daily.setdefault(d, {'date': d, 'input_tokens': 0, 'output_tokens': 0,
                             'cache_read_tokens': 0, 'cost_usd': 0.0, 'sessions': 0})
    out['daily'] = sorted(daily.values(), key=lambda x: x['date'])

    # 按模型
    bymodel = {}
    for s in sess:
        m = s['model'] or '(unknown)'
        b = bymodel.setdefault(m, {'model': m, 'sessions': 0, 'input_tokens': 0,
                                   'output_tokens': 0, 'cache_read_tokens': 0, 'cost_usd': 0.0})
        b['sessions'] += 1
        b['input_tokens'] += int(num(s['input_tokens']))
        b['output_tokens'] += int(num(s['output_tokens']))
        b['cache_read_tokens'] += int(num(s['cache_read_tokens']))
        b['cost_usd'] = round(b['cost_usd'] + num(s['estimated_cost_usd']), 4)
    out['by_model'] = sorted(bymodel.values(), key=lambda x: -x['input_tokens'])[:10]

    # 会话卡片（前 50）
    cards = []
    for s in sess[:50]:
        cards.append({
            'id': s['id'],
            'title': s['title'] or (s['id'][:12] + '…'),
            'model': s['model'],
            'profile': s['profile_name'],
            'messages': int(s['message_count'] or 0),
            'tool_calls': int(s['tool_call_count'] or 0),
            'api_calls': int(s['api_call_count'] or 0),
            'input_tokens': int(num(s['input_tokens'])),
            'output_tokens': int(num(s['output_tokens'])),
            'cache_read_tokens': int(num(s['cache_read_tokens'])),
            'cost_usd': round(num(s['estimated_cost_usd']), 4),
            'started_at': iso(s['started_at']),
            'last_activity_at': iso(s['last_activity_at']),
            'is_child': bool(s['parent_session_id']),
            'cwd': s['cwd'],
        })
    out['sessions'] = cards

elif mode == 'session':
    if not sid:
        print(json.dumps({'ok': False, 'error': 'session id required'})); sys.exit(0)
    rows = q("""select id, model, message_count, tool_call_count, input_tokens, output_tokens,
      cache_read_tokens, cache_write_tokens, reasoning_tokens, api_call_count,
      estimated_cost_usd, cost_status, started_at, ended_at, last_activity_at, title,
      parent_session_id, profile_name, cwd, system_prompt_hash, compression_ineffective_count,
      compression_overload_streak, rewind_count
      from sessions where id=?""", (sid,))
    if not rows:
        print(json.dumps({'ok': False, 'error': 'session not found', 'id': sid})); sys.exit(0)
    s = rows[0]

    def num(v):
        return float(v) if v is not None else 0.0

    # 六色上下文拆分（按 role 聚合字符→近似 token）
    # messages.token_count 在本栈恒为 NULL，故用字符数/2.2 近似中文 token，
    # 再按 sessions 的实测 input_tokens 做整体缩放，保证总量对齐。
    parts = q("""select role, count(*) n, coalesce(sum(length(content)),0) chars
      from messages where session_id=? group by role""", (sid,))
    approx = {}
    total_chars = 0
    for p in parts:
        total_chars += p['chars']
        approx[p['role']] = p['chars']
    # 系统提示词正文不在 sessions 表（恒为 NULL），按 system_prompt_hash 关联 system_prompts 表
    sys_chars = 0
    sp = q("""select length(prompt) as chars from system_prompts where hash=?""",
      (s['system_prompt_hash'] or '',))
    if sp and sp[0]['chars']:
        sys_chars = int(sp[0]['chars'])
    tool_chars = approx.get('tool', 0)
    user_chars = approx.get('user', 0)
    asst_chars = approx.get('assistant', 0)
    base = sys_chars + total_chars
    scale = (num(s['input_tokens']) / (base / 2.2)) if base > 0 and num(s['input_tokens']) > 0 else 1.0

    def tok(c):
        return int(round((c / 2.2) * scale))

    out['session'] = {
        'id': s['id'], 'title': s['title'] or s['id'][:12] + '…', 'model': s['model'],
        'profile': s['profile_name'], 'cwd': s['cwd'],
        'messages': int(s['message_count'] or 0), 'tool_calls': int(s['tool_call_count'] or 0),
        'api_calls': int(s['api_call_count'] or 0),
        'input_tokens': int(num(s['input_tokens'])), 'output_tokens': int(num(s['output_tokens'])),
        'cache_read_tokens': int(num(s['cache_read_tokens'])),
        'cache_write_tokens': int(num(s['cache_write_tokens'])),
        'reasoning_tokens': int(num(s['reasoning_tokens'])),
        'cost_usd': round(num(s['estimated_cost_usd']), 4),
        'cost_status': s['cost_status'],
        'started_at': iso(s['started_at']), 'ended_at': iso(s['ended_at']),
        'last_activity_at': iso(s['last_activity_at']),
        'is_child': bool(s['parent_session_id']),
        'rewind_count': int(s['rewind_count'] or 0),
    }
    out['composition'] = [
        {'key': 'system', 'label': '系统提示词', 'tokens': tok(sys_chars)},
        {'key': 'user', 'label': '用户消息', 'tokens': tok(user_chars)},
        {'key': 'assistant', 'label': '助手回复', 'tokens': tok(asst_chars)},
        {'key': 'tool', 'label': '工具结果', 'tokens': tok(tool_chars)},
    ]
    out['composition_total'] = sum(c['tokens'] for c in out['composition'])
    out['estimate_note'] = '逐消息 token_count 在本栈为 NULL，拆分值按字符数近似并按会话实测 input_tokens 缩放'

    # 工具使用分布
    out['tools'] = q("""select tool_name, count(*) n, coalesce(sum(length(content)),0) chars
      from messages where session_id=? and role='tool' and tool_name is not null
      group by tool_name order by n desc limit 15""", (sid,))

    # 子会话（Agent 家族）
    out['children'] = q("""select id, title, model, message_count, input_tokens, output_tokens,
      coalesce(last_activity_at, started_at) ts from sessions where parent_session_id=?
      order by ts desc limit 20""", (sid,))
    for c in out['children']:
        c['started_iso'] = iso(c.get('ts'))

    # 逐模型用量
    out['model_usage'] = q("""select model, task, api_call_count, input_tokens, output_tokens,
      cache_read_tokens, reasoning_tokens, round(coalesce(estimated_cost_usd,0),4) cost
      from session_model_usage where session_id=? order by input_tokens desc""", (sid,))

con.close()
print(json.dumps(out, ensure_ascii=False))
`

function runPy(mode: string, a1: string, a2: string): Promise<any> {
  return new Promise(resolve => {
    execFile(
      PYTHON,
      ['-c', SCRIPT, STATE_DB, mode, a1, a2],
      { timeout: TIMEOUT_MS, maxBuffer: 8 * 1024 * 1024 },
      (err, stdout) => {
        if (err) {
          resolve({ ok: false, error: String(err.message || err) })
          return
        }
        try {
          resolve(JSON.parse(stdout))
        } catch (e) {
          resolve({ ok: false, error: `parse error: ${String(e)}` })
        }
      },
    )
  })
}

/** GET /api/hermes/context/overview?days=30 */
export async function overview(ctx: Ctx): Promise<void> {
  const days = String(Math.min(Math.max(Number(ctx.query.days) || 30, 1), 365))
  const data = await runPy('overview', days, '')
  ctx.status = data.ok === false ? 200 : 200
  ctx.body = data
}

/** GET /api/hermes/context/session/:id */
export async function session(ctx: Ctx): Promise<void> {
  const id = String(ctx.params?.id || '').trim()
  if (!id) {
    ctx.status = 400
    ctx.body = { ok: false, error: 'session id required' }
    return
  }
  const data = await runPy('session', '30', id)
  ctx.body = data
}
