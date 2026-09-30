"""Local HN-shaped fixtures for the opt-in GUI integration test."""

import json
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

lock = threading.Lock()
active = peak = 0
attempts = {}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        global active, peak
        with lock:
            active += 1
            peak = max(peak, active)
            attempts[self.path] = attempts.get(self.path, 0) + 1
            attempt = attempts[self.path]
        try:
            if self.path == "/article":
                self.respond(
                    200,
                    b"<!doctype html><html><head><title>Smoke article</title>"
                    b"<meta name='viewport' content='width=device-width'></head>"
                    b"<body><h1>A story inside HN Reader</h1>"
                    b"<p>This page is served locally through WebKitGTK 6.0.</p>"
                    b"<p><a href='/second'>Continue reading</a></p></body></html>",
                    "text/html",
                )
            elif self.path == "/second":
                self.respond(
                    200,
                    b"<title>Second page</title><h1>Website navigation works</h1>",
                    "text/html",
                )
            elif self.path == "/stats":
                self.respond(200, json.dumps({"peak": peak, "attempts": attempts}).encode())
            elif self.path.endswith("stories.json"):
                time.sleep(0.15)
                self.respond(200, json.dumps(list(range(1, 32))).encode())
            elif self.path.startswith("/v0/item/"):
                item_id = int(self.path.split("/")[-1].removesuffix(".json"))
                time.sleep(0.05 + (item_id % 4) * 0.025)
                if item_id == 31 and attempt == 1:
                    self.respond(503, b"{}")
                    return
                self.respond(200, json.dumps(self.item(item_id)).encode())
            else:
                self.respond(404, b"{}")
        finally:
            with lock:
                active -= 1

    def item(self, item_id):
        if item_id == 101:
            return {"id": 101, "type": "comment", "deleted": True, "kids": [103]}
        if item_id >= 100:
            return {
                "id": item_id,
                "type": "comment",
                "by": "reader",
                "time": int(time.time()) - 1800,
                "text": (
                    "A native comment with <i>emphasis</i>, &amp; entities."
                    "<p><a href='https://example.com'>A useful link</a>"
                    "<pre>puts &quot;Hello, GNOME&quot;</pre>"
                ),
                "kids": [104] if item_id == 103 else [],
            }
        result = {
            "id": item_id,
            "type": "story",
            "title": f"Story {item_id}: Building a native reader for GNOME",
            "by": "hacker",
            "score": 125,
            "time": int(time.time()) - 3600,
            "descendants": 4,
            "kids": [100, 101],
        }
        if item_id == 2:
            result["text"] = (
                "Ask HN: What are you building?"
                "<p>A text-only post with <b>formatting</b>."
            )
        else:
            result["url"] = f"http://127.0.0.1:{self.server.server_port}/article"
        return result

    def respond(self, status, data, content_type="application/json"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass


def main():
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    Path(sys.argv[1]).write_text(str(server.server_port))
    server.serve_forever()


if __name__ == "__main__":
    main()
