const http2 = require('http2'), http = require('http');
const [h2port, h1port] = [+process.argv[2], +process.argv[3]];
http2.createServer().on('stream', (stream) => {
  stream.respond({ ':status': 200, 'content-type': 'application/grpc' }, { waitForTrailers: true });
  stream.on('wantTrailers', () => stream.sendTrailers({ 'grpc-status': '0' }));
  stream.end('ok');
}).on('error', () => {}).listen(h2port, '127.0.0.1');            // h2c, prior knowledge only
http.createServer((req, res) => { res.end('ok'); }).listen(h1port, '127.0.0.1'); // HTTP/1.1 only, no upgrade
setTimeout(() => process.exit(0), 60000);
