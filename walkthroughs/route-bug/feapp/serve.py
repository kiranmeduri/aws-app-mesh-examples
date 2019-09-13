#!/usr/bin/env python3

try:
    import os
    import socket
    import traceback
    from http.server import BaseHTTPRequestHandler, HTTPServer
    from urllib.request import Request, urlopen
    from urllib.error import URLError, HTTPError
except Exception as e:
    print(f'[ERROR] {e}')

COLOR_HOST = os.environ.get('COLOR_HOST')
print(f'COLOR_HOST is {COLOR_HOST}')

PORT = int(os.environ.get('PORT', '8080'))
print(f'PORT is {PORT}')

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            if self.path == '/ping':
                self.send_response(200)
                self.end_headers()
                return

            if self.path == '/config_dump':
                req = Request('http://localhost:9901/config_dump')
                res = urlopen(req)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(res.read())
                return

            if self.path == '/color/config_dump':
                req = Request(f'http://{COLOR_HOST}/config_dump')
                res = urlopen(req)
                self.send_response(200)
                self.end_headers()
                self.wfile.write(res.read())
                return


            req = Request(f'http://{COLOR_HOST}')
            res = urlopen(req)
            self.send_response(200)
            self.end_headers()
            self.wfile.write(res.read())

        except HTTPError as e:
            print(f'[ERROR] {traceback.format_exc()}')
            self.send_error(e.code, e.reason)

        except Exception as e:
            print(f'[ERROR] {traceback.format_exc()}')
            self.send_error(500, b'Something really bad happened')

print('starting server...')
httpd = HTTPServer(('', PORT), Handler)
print('running server...')
httpd.serve_forever()
