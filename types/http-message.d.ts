import * as http from 'http'
import * as net from 'net'

export declare interface RequestChannel {
    name: string;
    handleRequest: Function;
    runtimeAgent: any;
    config?: any;
}

export declare class ServerMessage extends http.Server {
    private logger;
    private dynChannels;
    private requests;
    private websockets;
    private currentTimeout;

    constructor(requestListener?: (res: http.IncomingMessage) => void);
    listen(channel: RequestChannel, cb?: Function): this;
    listen(port?: number, hostname?: string, backlog?: number, listeningListener?: Function): this;
    listen(port?: number, hostname?: string, listeningListener?: Function): this;
    listen(port?: number, backlog?: number, listeningListener?: Function): this;
    listen(port?: number, listeningListener?: Function): this;
    listen(path: string, backlog?: number, listeningListener?: Function): this;
    listen(path: string, listeningListener?: Function): this;
    listen(options: net.ListenOptions, listeningListener?: Function): this;
    listen(handle: any, backlog?: number, listeningListener?: Function): this;
    listen(handle: any, listeningListener?: Function): this;
    close(cb?: Function): this;
    setTimeout(msecs?: number, callback?: () => void): this;
    setTimeout(callback: () => void): this;
}