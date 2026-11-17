"""A stand-in for llama-server's /v1/chat/completions, for LlamaBrain's tests on the Mac.

The user message picks the behaviour, so each test can exercise one failure mode over real HTTP.
Usage: python3 -I fake_llama_server.py PORT     (binds 127.0.0.1 only)
"""
import http.server
import json
import sys
import time


def sse(obj):
    return ("data: " + json.dumps(obj) + "\n\n").encode()


def delta(text):
    return sse({"choices": [{"index": 0, "delta": {"content": text}, "finish_reason": None}]})


TOKEN = "ab" * 32  # the test token
FINISH = sse({"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
DONE = b"data: [DONE]\n\n"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if self.headers.get("Authorization") != "Bearer " + TOKEN:  # as llama-server with --api-key-file
            data = b'{"error":{"code":401,"message":"Invalid API Key","type":"authentication_error"}}'
            self.send_response(401)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        mode = body["messages"][-1]["content"]
        # Echo what the app sent, so tests can check the request itself.
        if mode == "echo":
            return self.stream([delta(json.dumps(body, sort_keys=True)), FINISH, DONE])
        if mode == "normal":
            return self.stream([delta("Try "), delta("git "), delta("rebase."), FINISH, DONE])
        if mode == "split":  # one event cut across chunks, and two events in one chunk
            whole = delta("Hello ") + delta("there.") + FINISH + DONE
            return self.stream([whole[:7], whole[7:30], whole[30:]])
        if mode == "markdown":
            return self.stream([delta("Run **`git status`**\n"), delta("```now```"), FINISH, DONE])
        if mode == "no-done":  # stream just ends
            return self.stream([delta("Cut "), delta("short")])
        if mode == "empty":
            return self.stream([FINISH, DONE])
        if mode == "error-event":
            return self.stream([sse({"error": {"code": 500, "message": "model failed to load"}})])
        if mode == "http500":
            data = b'{"error":{"message":"boom"}}'
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if mode == "slow":  # long pause before the first token (cold model load)
            time.sleep(1.5)
            return self.stream([delta("Awake."), FINISH, DONE])
        if mode == "trickle":  # keeps streaming for a while, for cancel tests
            return self.stream([delta("word ") for _ in range(30)] + [FINISH, DONE], pause=0.1)
        self.send_error(400, "unknown test mode")

    def stream(self, chunks, pause=0.02):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        try:
            for c in chunks:
                self.wfile.write(b"%x\r\n%s\r\n" % (len(c), c))
                self.wfile.flush()
                time.sleep(pause)
            self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            pass  # client cancelled


class Server(http.server.ThreadingHTTPServer):
    def handle_error(self, request, client_address):
        if isinstance(sys.exc_info()[1], (ConnectionResetError, BrokenPipeError)):
            return  # tests hang up on purpose (cancel, keep-alive)
        super().handle_error(request, client_address)


Server(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
