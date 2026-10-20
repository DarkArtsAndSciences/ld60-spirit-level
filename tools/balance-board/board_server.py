#!/usr/bin/env python3
"""Balance Board server: the 2011 Air reads the board, this Mac hands it to games.

    ssh oldair boardbridge  ->  this script  ->  ws://localhost:8765/ws  ->  the game

Runs `ssh oldair ~/boardbridge/boardbridge` (see boardbridge.m), and sends every reading to
every connected WebSocket client as JSON:

    {"tr": kg, "br": kg, "tl": kg, "bl": kg, "total": kg, "x": -1..1, "y": -1..1}
    {"info": "text"}          connection news from the Air, and from this script

x is right-positive and y is toes-positive, in the board's own frame (wiibrew's TR/BR/TL/BL).
Which way the player faces decides whether a game should flip them.

http://localhost:8765/ is a test page: a dot that follows your balance, and the raw numbers.
Python standard library only. Stop with Ctrl+C.

    python3 board_server.py                      the reader on another Mac: ssh oldair (default)
    python3 board_server.py --ssh HOST           the reader on another Mac, any ssh host
    python3 board_server.py --local ./boardbridge   the reader on this Mac (if it can pair the board)
"""

import asyncio
import base64
import hashlib
import json
import sys
from pathlib import Path

PORT = 8765
REMOTE = "exec ~/boardbridge/boardbridge"  # exec: the reader dies with the connection (SIGPIPE)
TEST_PAGE = Path(__file__).with_name("board_test.html")
FIELDS = ("tr", "br", "tl", "bl", "total", "x", "y")

clients: set[asyncio.StreamWriter] = set()


def frame(text: str) -> bytes:
    """One unmasked WebSocket text frame (server to client)."""
    data = text.encode()
    n = len(data)
    if n < 126:
        head = bytes([0x81, n])
    elif n < 65536:
        head = bytes([0x81, 126]) + n.to_bytes(2, "big")
    else:
        head = bytes([0x81, 127]) + n.to_bytes(8, "big")
    return head + data


def broadcast(message: dict) -> None:
    payload = frame(json.dumps(message, separators=(",", ":")))
    for w in list(clients):
        if w.is_closing():
            clients.discard(w)
            continue
        if w.transport.get_write_buffer_size() > 64_000:  # a stalled client: skip, don't queue
            continue
        w.write(payload)


def info(text: str) -> None:
    print(text, flush=True)
    broadcast({"info": text})


def reader_command() -> list:
    """The reader to run: over ssh (default: the host "oldair") or here, from the command line."""
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--local":
        return [args[1]]
    host = args[1] if len(args) == 2 and args[0] == "--ssh" else "oldair"
    return ["ssh", "-o", "ServerAliveInterval=5", "-o", "ConnectTimeout=8", host, REMOTE]


async def read_board() -> None:
    """Keep the reader running; restart it if it stops (or the SSH connection drops)."""
    command = reader_command()
    while True:
        info("starting the reader: " + " ".join(command))
        proc = await asyncio.create_subprocess_exec(
            *command, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        assert proc.stdout
        async for raw in proc.stdout:
            line = raw.decode(errors="replace").strip()
            if line.startswith("board "):
                parts = line.split()[1:]
                if len(parts) == len(FIELDS):
                    broadcast({k: float(v) for k, v in zip(FIELDS, parts)})
            elif line.startswith("info "):
                info("Air: " + line[5:])
        await proc.wait()
        info(f"the reader stopped (exit {proc.returncode}); trying again in 5 s")
        await asyncio.sleep(5)


async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 10)
    except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, asyncio.TimeoutError):
        writer.close()
        return
    lines = head.decode(errors="replace").split("\r\n")
    path = lines[0].split(" ")[1] if len(lines[0].split(" ")) > 1 else "/"
    headers = {k.strip().lower(): v.strip() for k, _, v in (l.partition(":") for l in lines[1:] if l)}

    if headers.get("upgrade", "").lower() != "websocket":
        body = TEST_PAGE.read_bytes() if path in ("/", "/index.html") else b"not found"
        status = "200 OK" if path in ("/", "/index.html") else "404 Not Found"
        writer.write(f"HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\n"
                     f"Content-Length: {len(body)}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".encode() + body)
        await writer.drain()
        writer.close()
        return

    accept = base64.b64encode(hashlib.sha1(
        (headers.get("sec-websocket-key", "") + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                  f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode())
    await writer.drain()
    clients.add(writer)
    print(f"client connected ({len(clients)} now)", flush=True)
    writer.write(frame(json.dumps({"info": "connected to the board server"})))
    try:
        # Clients only ever send close and ping; read frames until close or EOF.
        while True:
            b0, b1 = await reader.readexactly(2)
            n = b1 & 0x7F
            if n == 126:
                n = int.from_bytes(await reader.readexactly(2), "big")
            elif n == 127:
                n = int.from_bytes(await reader.readexactly(8), "big")
            mask = await reader.readexactly(4) if b1 & 0x80 else b""
            data = await reader.readexactly(n)
            if mask:
                data = bytes(c ^ mask[i % 4] for i, c in enumerate(data))
            opcode = b0 & 0x0F
            if opcode == 0x8:                               # close
                break
            if opcode == 0x9:                               # ping -> pong
                writer.write(bytes([0x8A, len(data)]) + data)
    except (asyncio.IncompleteReadError, ConnectionError):
        pass
    finally:
        clients.discard(writer)
        writer.close()
        print(f"client left ({len(clients)} now)", flush=True)


async def main() -> None:
    server = await asyncio.start_server(handle, "127.0.0.1", PORT)
    print(f"board server on http://localhost:{PORT}/ (test page) and ws://localhost:{PORT}/ws", flush=True)
    async with server:
        await asyncio.gather(server.serve_forever(), read_board())


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
