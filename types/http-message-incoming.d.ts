import { Readable } from 'stream'
import { EventEmitter } from 'events'

export interface IncomingMessageOptions {
    source: EventEmitter,
    originalMessage: any
}

export declare class IncomingMessage extends Readable {
    httpVersionManjor;
    httpVersionMinor;
    httpVersion;
    headers;
    rawHeaders;
    trailers;
    rawTrailers;
    url?: string;
    method?: string;
    statusCode?: number;
    statusMessage?: string;
    constructor(options: IncomingMessageOptions)
    setTimeout(msecs?: number, callback?: () => void): void;
    destroy(): void;
}