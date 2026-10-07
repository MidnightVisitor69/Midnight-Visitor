"""Serves ONLY pipeline/board.html on the local network, so the dev can check the board from a phone.
Any other path is 404: nothing else on this PC is exposed. Run: python serve_board.py [port]"""
import http.server, os, sys

BOARD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "board.html")
WAITING = (b"<!doctype html><meta name=viewport content='width=device-width'><meta http-equiv=refresh content=60>"
           b"<body style='background:#0d1226;color:#cfd6f5;font:16px system-ui;padding:24px'>"
           b"<h2>Job board not built yet</h2><p>The builder is still making it. This page checks again every minute.</p>")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?")[0] not in ("/", "/board.html"):
            self.send_error(404)
            return
        body = open(BOARD, "rb").read() if os.path.exists(BOARD) else WAITING
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8790
    http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
