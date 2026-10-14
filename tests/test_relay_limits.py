"""回环 TCP 验证中继的握手、帧长度及未入房连接预算。"""
import asyncio
import importlib.util
import json
from pathlib import Path
import struct
import sys
import unittest

spec = importlib.util.spec_from_file_location("etn_relay_limits", Path(__file__).resolve().parents[1] / "mod_sdk/coop_mod/server/relay_server.py")
relay = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = relay
spec.loader.exec_module(relay)


class ControlledWriter:
    """只控制传输水位；协议路由和帧编码使用真实服务端。"""
    def __init__(self, buffered=0):
        self.transport = self
        self.buffered = buffered
        self.closed = False
        self.frames = []

    def get_write_buffer_size(self): return self.buffered
    def is_closing(self): return self.closed
    def write(self, data): self.frames.append(data)
    def close(self): self.closed = True


class RelayBackpressure(unittest.IsolatedAsyncioTestCase):
    async def test_single_overflow_cannot_silently_lose_control(self):
        writer = ControlledWriter(relay.WRITE_HIGH_WATER)
        peer = relay.Peer(reader=None, writer=writer, id=2)
        await relay.send_control(peer, {"type": "peer_disconnected", "peer_id": 3})
        self.assertTrue(writer.closed or writer.frames, "可靠帧必须送达或明确断开，不能跳帧后继续连接")
        writer.buffered = 0
        await relay.send_data(peer, 1, b"next")
        self.assertTrue(writer.closed, "发生可靠性失败后不能恢复发送并遗忘丢帧")
        self.assertEqual(writer.frames, [])

    async def test_slow_receiver_does_not_block_healthy_broadcast(self):
        host = relay.Peer(reader=None, writer=ControlledWriter(), id=1)
        slow = relay.Peer(reader=None, writer=ControlledWriter(relay.WRITE_HIGH_WATER), id=2)
        healthy = relay.Peer(reader=None, writer=ControlledWriter(), id=3)
        room = relay.Room(code="TEST", host=host, clients={slow, healthy})
        for peer in (host, slow, healthy): peer.room = room
        packet = struct.pack("<i", 0) + b"reliable-event"
        await asyncio.wait_for(relay.route_packet(host, packet), 0.2)
        self.assertTrue(slow.writer.closed)
        self.assertEqual(healthy.writer.frames, [relay.encode_frame(2, struct.pack("<i", 1) + b"reliable-event")])


class RelayConcurrentAdmission(unittest.IsolatedAsyncioTestCase):
    async def asyncTearDown(self):
        relay.rooms.clear()

    async def test_pending_join_gets_fresh_roster_before_admission(self):
        host, first, second = [relay.Peer(reader=None, writer=ControlledWriter()) for _ in range(3)]
        await relay.handle_control(host, b'{"type":"create_room"}')
        join = json.dumps({"type": "join_room", "room_code": host.room.code}).encode()
        await relay.handle_control(first, join)
        await relay.handle_control(second, join)
        await relay.handle_control(first, b'{"type":"client_ready"}')
        await relay.handle_control(second, b'{"type":"client_ready"}')
        controls = []
        for frame in second.writer.frames:
            offset = 2 if frame[1] < 126 else 4
            controls.append(json.loads(frame[offset:]))
        known = set()
        for event in controls:
            known.update(p["peer_id"] for p in event.get("peers", []))
            if event["type"] in ("peer_pending", "peer_connected"):
                known.add(event["peer_id"])
            if event["type"] == "join_admitted":
                self.assertIn(first.id, known, "准入前必须知道同时加入的另一客机，未知 sender 数据会被永久拒收")
        await relay.route_packet(first, struct.pack("<i", second.id) + b"first-event")
        self.assertEqual(second.writer.frames[-1], relay.encode_frame(2, struct.pack("<i", first.id) + b"first-event"))


class RelayLimits(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.server = await asyncio.start_server(relay.handle_connection, "127.0.0.1", 0)
        self.port = self.server.sockets[0].getsockname()[1]
        self.writers = []
        self.saved = {}
        for name, value in (("HTTP_HANDSHAKE_TIMEOUT_SEC", 0.1), ("JOIN_TIMEOUT_SEC", 0.2), ("FRAME_TIMEOUT_SEC", 0.1)):
            self.saved[name] = getattr(relay, name, None)
            setattr(relay, name, value)

    async def asyncTearDown(self):
        for writer in self.writers:
            writer.close()
            await writer.wait_closed()
        self.server.close()
        await self.server.wait_closed()
        await asyncio.sleep(0.02)
        for name, value in self.saved.items():
            if value is None:
                delattr(relay, name)
            else:
                setattr(relay, name, value)
        relay.rooms.clear()

    async def connect(self, upgrade=True):
        reader, writer = await asyncio.open_connection("127.0.0.1", self.port)
        self.writers.append(writer)
        if upgrade:
            writer.write(b"GET / HTTP/1.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n")
            await writer.drain()
            self.assertIn(b"101 Switching Protocols", await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 1))
        return reader, writer

    async def test_oversized_frame_rejected_before_body(self):
        reader, writer = await self.connect()
        writer.write(b"\x82\xff" + struct.pack(">Q", 128 * 1024 * 1024) + b"\0\0\0\0")
        await writer.drain()
        self.assertEqual(await asyncio.wait_for(reader.read(), 0.5), b"")

    async def test_incomplete_http_handshake_expires(self):
        reader, writer = await self.connect(upgrade=False)
        writer.write(b"GET / HTTP/1.1\r\n")
        await writer.drain()
        self.assertEqual(await asyncio.wait_for(reader.read(), 0.5), b"")

    async def test_unjoined_socket_expires(self):
        reader, _ = await self.connect()
        self.assertEqual(await asyncio.wait_for(reader.read(), 0.5), b"")

    async def test_partial_frame_has_assembly_deadline(self):
        reader, writer = await self.connect()
        writer.write(b"\x82\xfe" + struct.pack(">H", 1000) + b"\0\0\0\0x")
        await writer.drain()
        self.assertEqual(await asyncio.wait_for(reader.read(), 0.5), b"")

    async def test_valid_control_frame_still_creates_room(self):
        reader, writer = await self.connect()
        payload = b'{"type":"create_room","player_name":"check"}'
        writer.write(bytes([0x81, 0x80 | len(payload)]) + b"\0\0\0\0" + payload)
        await writer.drain()
        response = await asyncio.wait_for(reader.read(4096), 0.5)
        self.assertIn(b'"type":"room_created"', response)


if __name__ == "__main__":
    unittest.main()
