"""Serves byte-world/tools/ and saves the PNG that icon.html POSTs to /save.

Usage: python3 -I tools/icon_server.py <output.png>   (from byte-world/), then open http://127.0.0.1:8001/icon.html
Binds to 127.0.0.1 only and exits after one successful save.
"""
import base64
import http.server
import os
import sys
import threading

OUT = sys.argv[1]
ROOT = os.path.dirname(os.path.abspath(__file__))
PREFIX = b"data:image/png;base64,"
MAX_BYTES = 8 * 1024 * 1024


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def do_POST(self):
        if self.path != "/save":
            return self.send_error(404)
        n = int(self.headers.get("Content-Length", 0))
        if not 0 < n <= MAX_BYTES:
            return self.send_error(413)
        body = self.rfile.read(n)
        if not body.startswith(PREFIX):
            return self.send_error(400, "expected a PNG data URL")
        png = base64.b64decode(body[len(PREFIX):], validate=True)
        if not png.startswith(b"\x89PNG\r\n\x1a\n"):
            return self.send_error(400, "not a PNG")
        with open(OUT, "wb") as f:
            f.write(png)
        self.send_response(200)
        self.end_headers()
        print(f"saved {len(png)} bytes to {OUT}", flush=True)
        threading.Thread(target=self.server.shutdown).start()


http.server.ThreadingHTTPServer(("127.0.0.1", 8001), Handler).serve_forever()
