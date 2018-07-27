import { ServerMessage } from './http-message'
import * as httpNode from 'http'
import { ClientRequest, RequestOptions } from './http-message-client'
import { IncomingMessage } from './http-message-incoming'

// Default class is ServerMessage (to be checked by JJ)
export default ServerMessage

// Other exported classes
export { ClientRequest, RequestOptions } from './http-message-client'
export { Agent } from './http-message-agent'
export { IncomingMessage } from './http-message-incoming'
export { getDynChannManager as _getDynChannManager } from './dynchannel-manager'

// Exported functions
export declare function createServer(requestListener?: (request:httpNode.IncomingMessage, response: httpNode.ServerResponse) => void): ServerMessage;
export declare function request(
    options: RequestOptions | httpNode.RequestOptions,
    callback?: ((res: IncomingMessage) => void) | ((res: httpNode.IncomingMessage) => void)): ClientRequest | httpNode.ClientRequest;