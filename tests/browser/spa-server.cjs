const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

const port = Number(process.env.PORT || 7357);
const root = path.resolve(process.cwd(), process.env.WEB_ROOT || 'build/web-browser');
const indexPath = path.join(root, 'index.html');

const contentTypes = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.ico': 'image/x-icon',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.wasm': 'application/wasm',
  '.webp': 'image/webp',
};

function sendFile(request, response, filePath) {
  const extension = path.extname(filePath).toLowerCase();
  response.writeHead(200, {
    'cache-control': 'no-store',
    'content-type': contentTypes[extension] || 'application/octet-stream',
  });
  if (request.method === 'HEAD') {
    response.end();
    return;
  }
  fs.createReadStream(filePath).pipe(response);
}

const server = http.createServer((request, response) => {
  if (request.method !== 'GET' && request.method !== 'HEAD') {
    response.writeHead(405, {allow: 'GET, HEAD'}).end();
    return;
  }

  let pathname;
  try {
    pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
  } catch (_) {
    response.writeHead(400).end('Invalid URL');
    return;
  }

  const requestedPath = path.resolve(root, `.${pathname}`);
  if (requestedPath !== root && !requestedPath.startsWith(`${root}${path.sep}`)) {
    response.writeHead(403).end('Forbidden');
    return;
  }

  fs.stat(requestedPath, (error, stats) => {
    if (!error && stats.isFile()) {
      sendFile(request, response, requestedPath);
      return;
    }
    sendFile(request, response, indexPath);
  });
});

server.listen(port, '127.0.0.1', () => {
  process.stdout.write(`Browser QA server: http://127.0.0.1:${port}\n`);
});

