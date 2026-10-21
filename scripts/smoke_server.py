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
        api_request = self.path.startswith("/v0/")
        with lock:
            # Soup's concurrency limit does not apply to WebKit resources.
            if api_request:
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
                    b"<body><nav>Website navigation</nav><article>"
                    b"<h1>A story inside HN Reader</h1>"
                    b"<p>This page is served locally through WebKitGTK 6.0. "
                    b"The native reader extracts the main article and presents it "
                    b"with GTK widgets that follow the selected application theme.</p>"
                    b"<p>Extra prose makes this fixture representative of an article "
                    b"instead of a navigation shell, while remaining deterministic "
                    b"and independent from the Internet.</p>"
                    b"<p><a href='/second'>Continue reading</a></p>"
                    b"<ol>\n<li><span aria-hidden='true'>1</span>\n"
                    b"<h3>Check</h3>\n<p>See what your public record says.</p></li>\n"
                    b"<li><span aria-hidden='true'>2</span>\n"
                    b"<h3>Watch</h3>\n<p>An email before it expires.</p></li></ol>"
                    b"<p><a href='/empty'>\n <svg><title>Icon</title></svg>\n </a></p>"
                    b"<pre><code>  first line\n    second line\n</code></pre>"
                    + (
                        b"<p>A long article paragraph for repeatable reading position tests. "
                        b"The native reader and original website have independent layouts.</p>"
                    ) * 60
                    + b"<img src='/slow-resource.svg' alt='Slow decorative resource'>"
                    b"</article></body></html>",
                    "text/html",
                )
            elif self.path == "/slow-resource.svg":
                time.sleep(3)
                self.respond(
                    200,
                    b"<svg xmlns='http://www.w3.org/2000/svg' width='1' height='1'/>",
                    "image/svg+xml",
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
                if api_request:
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
                "kids": {103: [104], 139: [201], 201: [301]}.get(item_id, []),
            }
        result = {
            "id": item_id,
            "type": "story",
            "title": f"Story {item_id}: Building a native reader for GNOME",
            "by": "hacker",
            "score": 125,
            "time": int(time.time()) - 3600,
            "descendants": 4,
            "kids": [100, 101] + list(range(110, 140)),
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
