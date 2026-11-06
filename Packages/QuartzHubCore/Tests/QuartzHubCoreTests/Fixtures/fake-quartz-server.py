# A stand-in for `npx quartz build [--serve --port P --wsPort W]` (BuildServerTests). It notes its
# call in $QH_FAKE_DIR/calls.log, prints what Quartz prints, and with --serve answers HTTP on P and
# holds W. $QH_FAKE_DIR/mode may say: "die" (exit 2 after the banner), "noline" (no "Started a
# Quartz server" line), "noline-nows" (neither the line nor the websocket port), "slow" (first build
# takes a second), "stubborn" (ignores SIGTERM). With $QH_FAKE_DIR/hold present it waits
# before building.
import os
import signal
import socket
import sys
import threading
import time

here = os.environ["QH_FAKE_DIR"]
args = sys.argv[1:]
with open(os.path.join(here, "calls.log"), "a") as calls:
    calls.write(f"{os.getpid()} {' '.join(args)} @ {os.getcwd()}\n")
mode = open(os.path.join(here, "mode")).read().strip() if os.path.exists(os.path.join(here, "mode")) else ""


def say(text, stream=sys.stdout):
    stream.write(text + "\n")
    stream.flush()


if mode == "stubborn":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
say("Quartz v5.0.0")
while os.path.exists(os.path.join(here, "hold")):
    time.sleep(0.02)
if mode == "die":
    say("Error: something broke", sys.stderr)
    sys.exit(2)
time.sleep(1 if mode == "slow" else 0.1)
say("Parsing input files using 8 threads")
say("Emitting files")
say("Done processing 3 files in 0.2s")
if "--serve" not in args:
    sys.exit(0)

port = int(args[args.index("--port") + 1])
ws_port = int(args[args.index("--wsPort") + 1])
page = b"<html><head><title>Fake</title><meta name=\"generator\" content=\"Quartz\"></head></html>"


def listen(number):
    server = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
    server.bind(("::", number))
    server.listen(16)
    return server


def serve_page(server):
    while True:
        connection, _ = server.accept()
        try:
            connection.recv(4096)
            connection.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % len(page) + page)
        finally:
            connection.close()


def hold(server):
    while True:
        server.accept()[0].close()


threading.Thread(target=serve_page, args=(listen(port),), daemon=True).start()
if mode != "noline-nows":
    threading.Thread(target=hold, args=(listen(ws_port),), daemon=True).start()
if not mode.startswith("noline"):
    say(f"Started a Quartz server listening at http://localhost:{port}")
while True:
    time.sleep(1)
