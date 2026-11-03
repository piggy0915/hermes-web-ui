import { request } from '../client'

/** 面板条目：一行一件需要人的事 */
export interface AttentionItem {
  what: string
  ref: string
  detail: string
  action: string
}

export interface AttentionPanelResponse {
  ok: boolean
  error?: string
  generated_at: string
  需要你决定?: AttentionItem[]
  系统问题?: AttentionItem[]
  计数?: Record<string, number>
}

export async function fetchAttentionPanel(): Promise<AttentionPanelResponse> {
  return request<AttentionPanelResponse>('/api/hermes/attention/panel')
}
