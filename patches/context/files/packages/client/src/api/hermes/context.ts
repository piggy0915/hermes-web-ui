import { request } from '../client'

/** 与后端 controllers/context.ts 一一对应的只读接口。 */

export interface ContextKpi {
  sessions: number
  api_calls: number
  input_tokens: number
  output_tokens: number
  cache_read_tokens: number
  cache_write_tokens: number
  reasoning_tokens: number
  total_tokens: number
  estimated_cost_usd: number
  cache_hit_rate: number
  cost_coverage: { priced: number; unknown: number }
}

export interface ContextDaily {
  date: string
  input_tokens: number
  output_tokens: number
  cache_read_tokens: number
  cost_usd: number
  sessions: number
}

export interface ContextSessionCard {
  id: string
  title: string
  model: string | null
  profile: string | null
  messages: number
  tool_calls: number
  api_calls: number
  input_tokens: number
  output_tokens: number
  cache_read_tokens: number
  cost_usd: number
  started_at: string | null
  last_activity_at: string | null
  is_child: boolean
  cwd: string | null
}

export interface ContextOverview {
  ok: boolean
  error?: string
  generated_at: string
  kpi: ContextKpi
  daily: ContextDaily[]
  by_model: Array<{
    model: string
    sessions: number
    input_tokens: number
    output_tokens: number
    cache_read_tokens: number
    cost_usd: number
  }>
  sessions: ContextSessionCard[]
}

export interface ContextCompositionPart {
  key: string
  label: string
  tokens: number
}

export interface ContextSessionDetail {
  ok: boolean
  error?: string
  generated_at: string
  session: {
    id: string
    title: string
    model: string | null
    profile: string | null
    cwd: string | null
    messages: number
    tool_calls: number
    api_calls: number
    input_tokens: number
    output_tokens: number
    cache_read_tokens: number
    cache_write_tokens: number
    reasoning_tokens: number
    cost_usd: number
    cost_status: string | null
    started_at: string | null
    ended_at: string | null
    last_activity_at: string | null
    is_child: boolean
    rewind_count: number
  }
  composition: ContextCompositionPart[]
  composition_total: number
  estimate_note: string
  tools: Array<{ tool_name: string; n: number; chars: number }>
  children: Array<{
    id: string
    title: string | null
    model: string | null
    message_count: number
    input_tokens: number
    output_tokens: number
    started_iso: string | null
  }>
  model_usage: Array<{
    model: string
    task: string
    api_call_count: number
    input_tokens: number
    output_tokens: number
    cache_read_tokens: number
    reasoning_tokens: number
    cost: number
  }>
}

export async function fetchContextOverview(days = 30): Promise<ContextOverview> {
  return request<ContextOverview>(`/api/hermes/context/overview?days=${days}`)
}

export async function fetchContextSession(id: string): Promise<ContextSessionDetail> {
  return request<ContextSessionDetail>(`/api/hermes/context/session/${encodeURIComponent(id)}`)
}
