#!/usr/bin/env python3

try:
    import os
    import socket
    from http.server import BaseHTTPRequestHandler, HTTPServer
except Exception as e:
    print(f'[ERROR] {e}')

COLOR = os.environ.get('COLOR', 'no color!')
print(f'COLOR is {COLOR}')

PORT = int(os.environ.get('PORT', '8080'))
print(f'PORT is {PORT}')

USE_IPV6 = bool(os.environ.get('USE_IPV6', False))
print(f'USE_IPV6 is {USE_IPV6}')

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/ping':
            self.send_response(200)
            self.end_headers()
            return
        self.send_response(200)
        self.end_headers()
        self.wfile.write(bytes(COLOR, 'utf8'))

class HTTPServerV6(HTTPServer):
    address_family = socket.AF_INET6

print('starting server...')

if USE_IPV6:
    httpd = HTTPServerV6(('::', PORT), Handler)
else:
    httpd = HTTPServer(('', PORT), Handler)

print('running server...')
httpd.serve_forever()
