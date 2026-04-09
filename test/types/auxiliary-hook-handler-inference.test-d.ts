import { expectAssignable, expectType } from 'tsd'
import fastify, {
  FastifyReply,
  FastifyRequest,
  FastifyTypeProvider,
  HookHandlerDoneFunction
} from '../../fastify'

const server = fastify()

interface AuxiliaryHandlerProvider extends FastifyTypeProvider { output: this['input'] }

function auxiliaryHandler (request: FastifyRequest, reply: FastifyReply, done: HookHandlerDoneFunction): void {
  done()
}

expectAssignable(server.withTypeProvider<AuxiliaryHandlerProvider>().get(
  '/',
  {
    onRequest: auxiliaryHandler,
    schema: { querystring: 'auxiliary-query' }
  },
  (req) => {
    expectType<'auxiliary-query'>(req.query)
  }
))

expectAssignable(server.withTypeProvider<AuxiliaryHandlerProvider>().get(
  '/',
  {
    preHandler: [auxiliaryHandler],
    schema: { body: 'auxiliary-body' }
  },
  (req) => {
    expectType<'auxiliary-body'>(req.body)
  }
))

expectAssignable(server.withTypeProvider<AuxiliaryHandlerProvider>().route({
  method: 'GET',
  url: '/',
  onRequest: auxiliaryHandler,
  schema: { params: 'auxiliary-params' },
  handler: (req) => {
    expectType<'auxiliary-params'>(req.params)
  }
}))
