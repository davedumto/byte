# A stand-in for the app's event listener, for tools/mac/test.sh. Usage: fake_byte.py PORT TOKEN LOGFILE
# Answers like EventRouter (202 / 200 / 401) and appends each request as one JSON line to LOGFILE.
import http.server, json, sys

PORT, TOKEN, LOG = int(sys.argv[1]), sys.argv[2], sys.argv[3]

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def handle_one(self, method):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n).decode() if n else ""
        ok = self.headers.get("Authorization") == "Bearer " + TOKEN
        with open(LOG, "a") as f:
            f.write(json.dumps({"method": method, "path": self.path, "auth": ok, "body": body}) + "\n")
        code = 401 if not ok else (200 if self.path == "/health" else 202)
        self.send_response(code); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"{}")
    def do_GET(self): self.handle_one("GET")
    def do_POST(self): self.handle_one("POST")

http.server.HTTPServer(("127.0.0.1", PORT), H).serve_forever()
