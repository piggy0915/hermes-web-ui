import Router from '@koa/router'
import * as ctrl from '../controllers/attention'

export const attentionRoutes = new Router()

attentionRoutes.get('/api/hermes/attention/panel', ctrl.panel)
