import { EventEmitter} from 'events'
import { IncomingMessage } from './http-message-incoming'
import * as q from 'q'

export interface RequestOptions {}

export declare class ClientRequest extends EventEmitter {
    private logger;
    private cb: Function;

    constructor(options: RequestOptions, cb?: (res: IncomingMessage) => void);
    write(chunk: any, cb?: Function): boolean;
    write(chunk: any, encoding?: string, cb?: Function): boolean;
    end(cb?: Function): void;
    end(chunk: any, cb?: Function): void;
    end(chunk: any, encoding?: string, cb?: Function): void;
    abort(): void;
    setTimeout(timeout: number, callback?: () => void): this;
    setNoDelay(noDelay?: boolean): void;
    setSocketKeepAlive(enable?: boolean, initialDelay?: number): void;
    onDynReply(request: any[]): q.Promise<any[][]>;
}