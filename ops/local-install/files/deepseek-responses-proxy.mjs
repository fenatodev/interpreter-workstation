import http from 'node:http';

const host = '127.0.0.1';
const port = Number(process.env.DEEPSEEK_PROXY_PORT || '1253');
const apiKey = process.env.DEEPSEEK_API_KEY;
if (!apiKey) {
  console.error('DEEPSEEK_API_KEY is required');
  process.exit(2);
}

const server = http.createServer(async (req, res) => {
  try {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = chunks.length ? Buffer.concat(chunks) : undefined;

    const headers = new Headers();
    const contentType = req.headers['content-type'];
    const accept = req.headers['accept'];
    if (contentType) headers.set('content-type', String(contentType));
    if (accept) headers.set('accept', String(accept));
    headers.set('authorization', 'Bearer ' + apiKey);

    const upstream = await fetch('https://api.deepseek.com' + (req.url || '/'), {
      method: req.method,
      headers,
      body: req.method === 'GET' || req.method === 'HEAD' ? undefined : body,
      redirect: 'manual',
    });

    res.statusCode = upstream.status;
    for (const name of ['content-type', 'cache-control', 'x-ds-trace-id']) {
      const value = upstream.headers.get(name);
      if (value) res.setHeader(name, value);
    }

    console.log(req.method, req.url, '->', upstream.status);

    if (!upstream.body) {
      res.end();
      return;
    }
    for await (const chunk of upstream.body) {
      if (!res.write(chunk)) {
        await new Promise(resolve => res.once('drain', resolve));
      }
    }
    res.end();
  } catch (error) {
    console.error('proxy_error', error instanceof Error ? error.message : String(error));
    if (!res.headersSent) res.statusCode = 502;
    res.end();
  }
});

server.listen(port, host, () => {
  console.log('deepseek_proxy_ready', host + ':' + port);
});

for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
