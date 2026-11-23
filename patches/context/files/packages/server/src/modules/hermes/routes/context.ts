import Router from '@koa/router'
import * as controller from '../controllers/context'

/**
 * 上下文洞察只读路由（对照 dsh-context 的 Context Insights）。
 * 前缀 /api/hermes/context，数据源为 Hermes state.db。
 */
export const contextRoutes = new Router()

contextRoutes.get('/api/hermes/context/overview', controller.overview)
contextRoutes.get('/api/hermes/context/session/:id', controller.session)
