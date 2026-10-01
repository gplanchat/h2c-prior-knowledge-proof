// gRPC server on @grpc/grpc-js answering grpc.health.v1.Health/Check with SERVING, cleartext, no TLS.
// Messages stay raw bytes: HealthCheckResponse{status: SERVING} is field 1, varint 1 => 0x08 0x01.
const grpc = require('@grpc/grpc-js');
const raw = (x) => x;
const server = new grpc.Server();
server.addService({
  Check: { path: '/grpc.health.v1.Health/Check', requestStream: false, responseStream: false,
           requestSerialize: raw, requestDeserialize: raw, responseSerialize: raw, responseDeserialize: raw },
}, { Check: (call, cb) => cb(null, Buffer.from([0x08, 0x01])) });
server.bindAsync(process.argv[2] || '127.0.0.1:50052', grpc.ServerCredentials.createInsecure(), (err) => {
  if (err) { console.error(err); process.exit(1); }
});
