[![semantic-release](https://img.shields.io/badge/%20%20%F0%9F%93%A6%F0%9F%9A%80-semantic--release-e10079.svg)](https://github.com/semantic-release/semantic-release)

# Http Message

Http server for Kumori Platform components.

## Description

This library extends [NodeJS HTTP server](https://nodejs.org/dist/latest-v8.x/docs/api/http.html) to support Kumori's channels (see [Kumori's documentation](https://github.com/kumori-systems/documentation) for more information about channels and Kumori's _service application model_).

```javascript
const http = require('@kumori/http-message')
let server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end('okay');
})
server.listen(channel, (error) => {
    // Do something
})
```

This HTTP server is compatible with most of the existing http frameworks like [ExpressJS](http://expressjs.com).

## Table of Contents

* [Installation](#installation)
* [Usage](#usage)
  * [`Hello World Server`](#hello-world-server)
  * [`Hello World Client`](#hello-world-client)
* [License](#license)

## Installation

Install it as a npm package

    npm install -g @kumori/http-message

## Usage

Kumori Platform incorporates a communication mechanism specifically designed for elastic software and is based on channels. A channel is an object a service component can use to communicate with other components. In this document we assume you already know what a Kumori component. If that is not the case, please refere to [Kumori's documentation](https://github.com/kumori-systems/documentation).

Http Message package has been developed specifically for Kumori's channels. It mimmics `http` NodeJS server API but changes some methods to use Kumori's channels instead of ports, IPs and/or domains. Let's see it in a couple of examples.

### Simple Server

This is a simple hello world server encapsulated in a Kumori's component. It is based on the [example](https://nodejs.org/dist/latest-v8.x/docs/api/synopsis.html) used in NodeJS documentation.

```javascript
const BaseComponent = require('component');
const http = require('@kumori/http-message');

class Component extends BaseComponent {

  constructor
    (runtime
    ,role
    ,iid
    ,incnum
    ,localData
    ,resources
    ,parameters
    ,dependencies
    ,offerings
    ) {
      super(runtime, role, iid, incnum, localData, resources, parameters, dependencies, offerings);
      this.httpChannel = offerings.endpoint;
  }

  run () {
    super.run();
    const server = http.createServer();
    server.on('request', (req, res) => {
      res.statusCode = 200;
      res.setHeader('Content-Type', 'text/plain');
      res.end('Hello World\n');
    });

    server.listen(this.httpChannel);
  }
}
module.exports = Component;
```

### Simple Client

Http Message can be also used to communicate with an http server deployed as a Kumori component.

```javascript
const BaseComponent = require('component');
const http = require('@kumori/http-message');

class Component extends BaseComponent {

  constructor
    (runtime
    ,role
    ,iid
    ,incnum
    ,localData
    ,resources
    ,parameters
    ,dependencies
    ,offerings
    ) {
      super(runtime, role, iid, incnum, localData, resources, parameters, dependencies, offerings);
      this.httpChannel = offerings.endpoint;
  }

  run () {
    super.run();
    const options = {
      channel: this.httpChannel,
      method: 'POST',
      path: '/upload'
    };
    const req = http.request(options, (res) => {
      res.on('data', (chunk) => {
        doThings(chunk)
      });
      res.on('end', () => {
        doThings()
      }
    });

    req.on('error', (e) => {
      doThings(e)
    });

    req.write(dataToSend);
    req.end();
  }
}
module.exports = Component;
```

**WARNIG**: currently, `setTimeout` and `abort` method are not supported.

## License

MIT © Kumori Systems
