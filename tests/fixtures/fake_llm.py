#!/usr/bin/env python3
"""A local stand-in for the assistant's providers: no real API is ever called.

    fake_llm.py LOGFILE [PORT]

Listens on 127.0.0.1, prints the port it took, and answers the three protocols
eva speaks. Each request is appended to LOGFILE as one JSON line. A key other
than FAKE_KEY (default sk-eva-test) is refused. What the last user message says
picks the reply: "slow" drips forever, "boom" answers 500, "long" is cut short,
and anything else streams a reply with markup and a code block.
"""
import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = sys.argv[1]
KEY = os.environ.get("FAKE_KEY", "sk-eva-test")
MODELS = ["fake-small", "fake-large"]


def reply_for(text):
    return [
        "Hello from the **stand-in**. ",
        "You said: `" + text[:60] + "`\n\n",
        "- first point\n- second point\n\n",
        "```python\n",
        "print('streamed')\n",
        "```\n",
        "Done.",
    ]


def text_of(content):
    if isinstance(content, str):
        return content
    return " ".join(part.get("text", "") for part in content if isinstance(part, dict))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, *_):
        pass

    def record(self, body):
        headers = {k.lower(): v for k, v in self.headers.items()}
        with open(LOG, "a") as out:
            out.write(json.dumps({"path": self.path, "method": self.command, "headers": headers, "body": body}) + "\n")

    def answer(self, status, payload):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authorised(self):
        given = self.headers.get("x-api-key") or (self.headers.get("authorization") or "").replace("Bearer ", "")
        if given == KEY:
            return True
        self.answer(401, {"error": {"type": "authentication_error", "message": "invalid key"}})
        return False

    def do_GET(self):
        self.record(None)
        if self.path == "/api/tags":
            self.answer(200, {"models": [{"name": name} for name in MODELS]})
        elif self.path.endswith("/models"):
            if self.authorised():
                self.answer(200, {"data": [{"id": name} for name in MODELS]})
        else:
            self.answer(404, {"error": "no such path"})

    def stream_open(self, kind):
        self.send_response(200)
        self.send_header("content-type", kind)
        self.end_headers()

    def emit(self, line):
        self.wfile.write(line.encode() + b"\n")
        self.wfile.flush()

    def do_POST(self):
        length = int(self.headers.get("content-length", 0))
        body = json.loads(self.rfile.read(length))
        self.record(body)
        last = text_of(body["messages"][-1]["content"]) if body.get("messages") else ""
        if self.path.endswith("/api/chat"):
            return self.ollama(last)
        if not self.authorised():
            return None
        if "boom" in last:
            return self.answer(500, {"error": {"message": "the fake server fell over"}})
        if self.path.endswith("/v1/messages"):
            return self.anthropic(last)
        if self.path.endswith("/chat/completions"):
            return self.openai(last)
        return self.answer(404, {"error": {"message": "no such path"}})

    def drip(self, last, send):
        if "slow" in last:
            for _ in range(600):
                send("tick ")
                time.sleep(0.1)
            return
        for piece in reply_for(last):
            send(piece)
            time.sleep(0.01)

    def anthropic(self, last):
        self.stream_open("text/event-stream")
        def event(payload):
            self.emit("event: " + payload["type"])
            self.emit("data: " + json.dumps(payload))
            self.emit("")
        event({"type": "message_start", "message": {"id": "msg_fake", "role": "assistant"}})
        event({"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}})
        self.drip(last, lambda piece: event({"type": "content_block_delta", "index": 0,
                                             "delta": {"type": "text_delta", "text": piece}}))
        event({"type": "content_block_stop", "index": 0})
        event({"type": "message_delta", "delta": {"stop_reason": "max_tokens" if "long" in last else "end_turn"}})
        event({"type": "message_stop"})

    def openai(self, last):
        self.stream_open("text/event-stream")
        def chunk(piece, reason=None):
            payload = {"choices": [{"delta": {"content": piece} if piece else {}, "finish_reason": reason}]}
            self.emit("data: " + json.dumps(payload))
            self.emit("")
        self.drip(last, chunk)
        chunk(None, "length" if "long" in last else "stop")
        self.emit("data: [DONE]")

    def ollama(self, last):
        self.stream_open("application/x-ndjson")
        self.drip(last, lambda piece: self.emit(json.dumps({"message": {"role": "assistant", "content": piece},
                                                            "done": False})))
        self.emit(json.dumps({"done": True, "done_reason": "stop"}))


def main():
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.daemon_threads = True
    print(server.server_address[1], flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
