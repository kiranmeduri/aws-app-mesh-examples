#!/usr/bin/env python3

try:
    import os
    import socket
    from http.server import BaseHTTPRequestHandler, HTTPServer
    import requests
    from dns import resolver
    import random
except Exception as e:
    print(f'[ERROR] {e}')

COLOR_HOST = os.environ.get('COLOR_HOST')
print(f'COLOR_HOST is {COLOR_HOST}')

RESOLVER_TYPE = os.environ.get('RESOLVER_TYPE', 'STATIC')
print(f'RESOLVER_TYPE is {RESOLVER_TYPE}')

PROXY_EGRESS_PORT = int(os.environ.get('PROXY_EGRESS_PORT', 15001))
print(f'PROXY_EGRESS_PORT is {PROXY_EGRESS_PORT}')

PORT = int(os.environ.get('PORT', '8080'))
print(f'PORT is {PORT}')

SIDECAR_PROXY_EGRESS_ADDRESS = f'127.0.0.1:{PROXY_EGRESS_PORT}'

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/ping':
            self.send_response(200)
            self.end_headers()
            return

        try:
            color_host = self._resolve_color_host()
            headers = {'Host': color_host}
            request_host=color_host
            if PROXY_EGRESS_PORT:
                request_host=SIDECAR_PROXY_EGRESS_ADDRESS

            print(f'[INFO] using request_host={request_host}, headers={headers}')
            response = requests.get(f'http://{request_host}', headers=headers)

            if response:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(response.content)
            else:
                self.send_error(code=response.status_code, message=response.reason)
        except Exception as e:
            print(f'[ERROR] {e}')
            self.send_error(500, b'Something really bad happened')

    def _resolve_color_host(self):
        if RESOLVER_TYPE != 'SRV':
            return COLOR_HOST

        #resolve using SRV
        try:
            fqdn=COLOR_HOST.split(':')[0]
            records = resolver.query(fqdn, 'SRV')
            record = records[0] #random.choice(records)
            print(f'Record = {repr(record)}')
            return f'{record.target}:{record.port}'
        except Exception as e:
            print(f'[INFO] error using SRV lookup {e}, using {COLOR_HOST}')
            return COLOR_HOST

print('starting server...')
httpd = HTTPServer(('', PORT), Handler)
print('running server...')
httpd.serve_forever()
