// Raw TCP listener: logs the first bytes each client sends, then closes. Proves what goes on the wire.
const net = require('net');
const port = +process.argv[2];
net.createServer((s) => {
  let buf = Buffer.alloc(0);
  s.on('data', (d) => { buf = Buffer.concat([buf, d]); });
  setTimeout(() => {
    const first = buf.toString('latin1').split('\r\n')[0];
    const up = /^upgrade:\s*(.*)$/im.exec(buf.toString('latin1'));
    console.log(JSON.stringify({ firstLine: first.slice(0, 40), hex: buf.subarray(0, 24).toString('hex'), upgradeHeader: up ? up[1] : null }));
    s.destroy();
  }, 400);
}).listen(port, '127.0.0.1');
setTimeout(() => process.exit(0), 40000);
