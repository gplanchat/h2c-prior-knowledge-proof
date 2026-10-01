<?php
// One unary call, grpc.health.v1.Health/Check with an empty request, on a cleartext gRPC server.
// Usage: php probe-grpc.php <client> <host:port>   (VARIANT_DIR points at sf7 or sf8)
require getenv('VARIANT_DIR').'/vendor/autoload.php';
[$which, $hostPort] = [$argv[1], $argv[2]];
$url = "http://$hostPort/grpc.health.v1.Health/Check";
$frame = "\0\0\0\0\0";                                   // gRPC message prefix, empty protobuf message
$grpcHeaders = ['content-type' => 'application/grpc', 'te' => 'trailers'];
$line = fn (string $s) => print($s."\n");
try {
  switch ($which) {
    case 'curl-20': case 'curl-prior':
      $trailers = []; $ch = curl_init($url);
      curl_setopt_array($ch, [
        CURLOPT_HTTP_VERSION => $which === 'curl-prior' ? CURL_HTTP_VERSION_2_PRIOR_KNOWLEDGE : CURL_HTTP_VERSION_2_0,
        CURLOPT_POST => 1, CURLOPT_POSTFIELDS => $frame, CURLOPT_TIMEOUT => 3, CURLOPT_RETURNTRANSFER => 1,
        CURLOPT_HTTPHEADER => ['content-type: application/grpc', 'te: trailers'],
        CURLOPT_HEADERFUNCTION => function ($ch, $l) use (&$trailers) { if (stripos($l, 'grpc-status') === 0) $trailers[] = trim($l); return strlen($l); },
      ]);
      $body = curl_exec($ch);
      $line($body === false ? 'FAIL: '.curl_error($ch) : 'OK status='.curl_getinfo($ch, CURLINFO_RESPONSE_CODE).' body='.bin2hex($body).' trailers='.json_encode($trailers));
      break;
    case 'sf-curl': case 'sf-amp':
      $client = $which === 'sf-curl' ? new Symfony\Component\HttpClient\CurlHttpClient() : new Symfony\Component\HttpClient\AmpHttpClient();
      $r = $client->request('POST', $url, ['http_version' => '2.0', 'headers' => $grpcHeaders, 'body' => $frame, 'timeout' => 3]);
      $body = $r->getContent(false);
      $line('OK status='.$r->getStatusCode().' body='.bin2hex($body).' trailers_info='.json_encode($r->getInfo('trailers')));
      break;
    case 'amp-only2':
      $c = Amp\Http\Client\HttpClientBuilder::buildDefault();
      $req = new Amp\Http\Client\Request($url, 'POST', $frame); $req->setProtocolVersions(['2']); $req->setTransferTimeout(3);
      foreach ($grpcHeaders as $k => $v) $req->setHeader($k, $v);
      $resp = $c->request($req, new Amp\NullCancellation()); $body = $resp->getBody()->buffer();
      $line('OK status='.$resp->getStatus().' body='.bin2hex($body).' trailers='.json_encode($resp->getTrailers()->await()->getHeaders()));
      break;
  }
} catch (Throwable $e) { $line('FAIL: '.get_class($e).': '.substr($e->getMessage(), 0, 110)); }
