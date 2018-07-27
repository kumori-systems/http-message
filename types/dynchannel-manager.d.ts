import { Agent } from './http-message-agent'
import * as q from 'q'

interface ReplyChannel {
    handleRequest: Function;
}

interface DynChannelManagerOptions {
    expireTime?: number;
}

export declare class DynChannManager {
    private logger;
    constructor(options: any);
    close(): void;
    getInstancePromise(staRequest: any, agent: Agent): q.Promise<any>;
    addInstancePromise(staRequest: any, agent: Agent, promise: q.Promise<any>): void;
    resetInstancePromise(staRequest: any, agent: Agent): void;
    getDynReply(staRequest: any): ReplyChannel;
    addRequest(request: any): void;
    removeRequest(reqId: string): void;
    checkRequest(reqId: string): any;
}

export declare function getDynChannManager(options?: any): DynChannManager;