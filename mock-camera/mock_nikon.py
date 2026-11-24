#!/usr/bin/env python3
"""
Mock Nikon camera speaking PTP/IP (as in "Connect to smart device > Wi-Fi connection" mode),
for testing the app's Nikon driver without a camera.

  * PTP/IP on TCP 15740: command channel (Init Command Request/Ack) and event channel
    (Init Event Request/Ack), then PTP operations with data phases in both directions.
  * Default: a Z 6II-like body (exposure time in Nikon's 0xD100 numerator/denominator form,
    InitiateCaptureRecInMedia 0x9207, GetEventEx 0x941C, movie recording, 384-byte live-view header).
  * --dslr: a D750-like body (0x500D in 1/10000 s, InitiateCapture 0x100E, GetEvent 0x90C7,
    no movie, 128-byte live-view header).
  * Live view: StartLiveView 0x9201 makes DeviceReady 0x90C8 answer Busy for a moment, then
    GetLiveViewImg 0x9203 returns a header + JPEG.
  * Card: one folder with JPG (+ NEF) files: GetStorageIDs, GetObjectHandles, GetObjectInfo,
    GetThumb, Nikon GetLargeThumb, GetObject and GetPartialObject.

    python3 mock_nikon.py                 # PTP/IP on 127.0.0.1:15740
    python3 mock_nikon.py --dslr          # behave like a D750
    python3 mock_nikon.py --bind 0.0.0.0  # reachable from a real iPhone on your Wi-Fi

In the app: Connect screen > Nikon (or Auto) > Advanced > Camera address = 127.0.0.1:15740.
"""
import argparse
import datetime
import os
import random
import socket
import socketserver
import struct
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mock_penf import load_frames  # noqa: E402  (same live-view frames as the PEN-F mock)

OK, BUSY, NOT_SUPPORTED, INVALID_VALUE, SESSION_OPEN = 0x2001, 0x2019, 0x2005, 0x201C, 0x201E
NOT_LIVE_VIEW = 0xA00B
MF_DRIVE_STEP_END = 0xA00C
STORAGE = 0x00010001

# PTP data types
UINT8, INT16, UINT16, UINT32, STR = 0x0002, 0x0003, 0x0004, 0x0006, 0xFFFF

F_NUMBERS = [180, 200, 220, 250, 280, 320, 350, 400, 450, 500, 560, 630, 710, 800, 900, 1000, 1100, 1300,
             1400, 1600]
ISOS = [100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000,
        6400, 8000, 10000, 12800, 25600, 51200]
BIAS = [round(t * 1000 / 3) for t in range(-15, 16)]
WB = [2, 4, 5, 6, 7, 0x8010, 0x8011, 0x8012, 0x8013]
SHUTTER_SECONDS = [30, 25, 20, 15, 13, 10, 8, 6, 5, 4, 3, 2.5, 2, 1.6, 1.3, 1, 0.8, 0.6, 0.5, 0.4]
SHUTTER_DENOMS = [3, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30, 40, 50, 60, 80, 100, 125, 160, 200, 250, 320, 400,
                  500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000]


def packed_shutters():
    values = [0xFFFFFFFF, 0xFFFFFFFD]   # bulb, time
    for s in SHUTTER_SECONDS:
        values.append((int(s * 10) << 16 | 10) if s != int(s) else (int(s) << 16 | 1))
    return values + [(1 << 16) | d for d in SHUTTER_DENOMS]


def tenthousandths_shutters():
    values = [0xFFFFFFFF] + [int(s * 10000) for s in SHUTTER_SECONDS]
    return values + [max(1, round(10000 / d)) for d in SHUTTER_DENOMS]


def shutter_seconds(value, packed):
    if value >= 0xFFFFFFFC:
        return 0
    if packed:
        return (value >> 16) / max(1, value & 0xFFFF)
    return value / 10000


# ---- packing helpers -----------------------------------------------------------------------

def ptp_string(text):
    if not text:
        return b"\x00"
    units = (text + "\x00").encode("utf-16-le")
    return bytes([len(text) + 1]) + units


def u16_array(values):
    return struct.pack("<I", len(values)) + b"".join(struct.pack("<H", v) for v in values)


def u32_array(values):
    return struct.pack("<I", len(values)) + b"".join(struct.pack("<I", v) for v in values)


FMT = {UINT8: "<B", INT16: "<h", UINT16: "<H", UINT32: "<I"}


def pack_value(dtype, value):
    return struct.pack(FMT[dtype], value)


def unpack_value(dtype, data):
    return struct.unpack(FMT[dtype], data[:struct.calcsize(FMT[dtype])])[0]


def packet(ptype, payload=b""):
    return struct.pack("<II", 8 + len(payload), ptype) + payload


# ---- camera state --------------------------------------------------------------------------

class Prop:
    def __init__(self, code, dtype, value, allowed=None, settable=True, rng=None):
        self.code, self.dtype, self.value = code, dtype, value
        self.allowed, self.settable, self.range = allowed, settable, rng

    def desc(self):
        data = struct.pack("<HHB", self.code, self.dtype, 1 if self.settable else 0)
        data += pack_value(self.dtype, self.value) * 2   # factory default, current
        if self.range:
            data += b"\x01" + b"".join(pack_value(self.dtype, v) for v in self.range)
        elif self.allowed:
            data += b"\x02" + struct.pack("<H", len(self.allowed)) + b"".join(pack_value(self.dtype, v) for v in self.allowed)
        else:
            data += b"\x00"
        return data


class MockNikon:
    def __init__(self, frames, dslr=False):
        self.lock = threading.Lock()
        self.frames = frames
        self.frame_index = 0
        self.dslr = dslr
        self.model = "D750" if dslr else "Z 6_2"
        self.session = False
        self.live_view = False
        self.busy_until = 0
        self.recording = False
        self.events = []
        self.next_handle = 2
        self.objects = {1: {"name": "100NCD750" if dslr else "100NZ6_2", "folder": True, "parent": 0,
                            "date": datetime.datetime.now(), "data": b"", "format": 0x3001}}
        shutters = tenthousandths_shutters() if dslr else packed_shutters()
        self.shutter_code = 0x500D if dslr else 0xD100
        default_shutter = 80 if dslr else (1 << 16 | 125)
        self.props = {
            0x5001: Prop(0x5001, UINT8, 82, settable=False, rng=(0, 100, 1)),
            0x5005: Prop(0x5005, UINT16, 2, WB),
            0x5007: Prop(0x5007, UINT16, 400, F_NUMBERS),
            0x5008: Prop(0x5008, UINT32, 5000, settable=False),
            0x500E: Prop(0x500E, UINT16, 1, [1], settable=False),       # mode dial on M
            0x500F: Prop(0x500F, UINT16, 400, ISOS),
            0x5010: Prop(0x5010, INT16, 0, BIAS),
            0xD054: Prop(0xD054, UINT8, 0, [0, 1]),
            self.shutter_code: Prop(self.shutter_code, UINT32, default_shutter, shutters),
        }
        start = datetime.datetime.now() - datetime.timedelta(days=1)
        for k in range(40):
            self.add_picture(start + datetime.timedelta(minutes=k * 15), raw=(k % 3 == 0), quiet=True)

    def add_picture(self, when=None, raw=False, movie=False, quiet=False):
        number = 1000 + self.next_handle
        prefix = "DSC" if self.dslr else "_DSC"
        base = f"{prefix}_{number:04d}"[:8] if self.dslr else f"_DSC{number:04d}"
        jpeg = self.frames[(number * 7) % len(self.frames)]
        names = [(base + (".MOV" if movie else ".JPG"), jpeg, 0x300D if movie else 0x3801)]
        if raw:
            names.append((base + ".NEF", random.Random(number).randbytes(2_500_000), 0x3000))
        added = []
        for name, data, fmt in names:
            handle = self.next_handle
            self.next_handle += 1
            self.objects[handle] = {"name": name, "folder": False, "parent": 1, "date": when or datetime.datetime.now(),
                                    "data": data, "format": fmt, "jpeg": jpeg}
            added.append(handle)
        if not quiet:
            print(f"  new file {names[0][0]} (handle {added[0]})")
        return added

    def operations(self):
        ops = [0x1001, 0x1002, 0x1003, 0x1004, 0x1007, 0x1008, 0x1009, 0x100A, 0x1014, 0x1015, 0x1016, 0x101B,
               0x90C1, 0x90C2, 0x90C4, 0x90C8, 0x9201, 0x9202, 0x9203, 0x9204, 0x9205]
        if self.dslr:
            return ops + [0x100E, 0x90C0, 0x90C7]
        return ops + [0x9207, 0x920A, 0x920B, 0x941C]

    def device_info(self):
        data = struct.pack("<HIH", 100, 0x0000000A, 100) + ptp_string("microsoft.com: 1.0; nikon.com: 1.0;")
        data += struct.pack("<H", 0)
        data += u16_array(self.operations()) + u16_array([0x4002, 0x400D, 0xC101, 0xC102])
        data += u16_array(sorted(self.props)) + u16_array([0x3801]) + u16_array([0x3801, 0x3000, 0x300D])
        data += ptp_string("Nikon Corporation") + ptp_string(self.model) + ptp_string("V1.50") + ptp_string("MOCK0001")
        return data

    def object_info(self, handle):
        o = self.objects[handle]
        date = o["date"].strftime("%Y%m%dT%H%M%S")
        data = struct.pack("<IHHI", STORAGE, o["format"], 0, len(o["data"]))
        data += struct.pack("<HIIIIIIIHII", 0x3808, 0 if o["folder"] else 8000, 160, 120,
                            0 if o["folder"] else 6048, 0 if o["folder"] else 4024, 24, o["parent"],
                            1 if o["folder"] else 0, 0, 0)
        data += ptp_string(o["name"]) + ptp_string(date) + ptp_string(date) + ptp_string("")
        return data

    def live_view_image(self):
        frame = self.frames[self.frame_index % len(self.frames)]
        self.frame_index += 1
        header = bytearray(128 if self.dslr else 384)
        struct.pack_into(">HH", header, 0, 640, 424)
        return bytes(header) + frame

    # Returns (response code, data for the initiator or None).
    def operation(self, op, params, data_out):
        p = params + [0] * 5
        if op == 0x1002:
            if self.session:
                return SESSION_OPEN, None
            self.session = True
            return OK, None
        if op == 0x1001:
            return OK, self.device_info()
        if not self.session:
            return 0x2003, None   # session not open
        if op not in self.operations():
            return NOT_SUPPORTED, None
        now = time.time()
        if op == 0x1003:
            self.session = False
            self.live_view = False
            return OK, None
        if op == 0x1014:
            prop = self.props.get(p[0])
            return (OK, prop.desc()) if prop else (0x200A, None)
        if op == 0x1015:
            prop = self.props.get(p[0])
            return (OK, pack_value(prop.dtype, prop.value)) if prop else (0x200A, None)
        if op == 0x1016:
            prop = self.props.get(p[0])
            if prop is None or not prop.settable:
                return 0x200A if prop is None else 0x200E, None   # access denied
            value = unpack_value(prop.dtype, data_out or b"\x00" * 8)
            if prop.allowed and value not in prop.allowed:
                print(f"  refused {p[0]:#06x} = {value:#x}")
                return INVALID_VALUE, None
            prop.value = value
            print(f"  set {p[0]:#06x} = {value:#x}")
            return OK, None
        if op == 0x90C8:
            return (BUSY if now < self.busy_until else OK), None
        if op == 0x90C2:
            return OK, None
        if op == 0x9201:
            self.live_view = True
            self.busy_until = now + 0.4
            print("  live view on")
            return OK, None
        if op == 0x9202:
            self.live_view = False
            print("  live view off")
            return OK, None
        if op == 0x9203:
            if not self.live_view:
                return NOT_LIVE_VIEW, None
            if now < self.busy_until:
                return BUSY, None
            return OK, self.live_view_image()
        if op == 0x9204:
            # MfDrive: direction 1 = towards the closest point, 2 = towards infinity; amount 1-32767.
            if not self.live_view:
                return NOT_LIVE_VIEW, None
            if now < self.busy_until:
                return BUSY, None
            direction, amount = (list(p) + [0, 0])[:2]
            position = getattr(self, "focus_pos", 2000)
            target = position + amount if direction == 2 else position - amount
            if (direction == 2 and position >= 10000) or (direction == 1 and position <= 0):
                print("  focus at the end of travel")
                return MF_DRIVE_STEP_END, None
            self.focus_pos = max(0, min(10000, target))
            self.busy_until = now + 0.15
            print(f"  focus {'far' if direction == 2 else 'near'} {amount} -> {self.focus_pos}/10000")
            return OK, None
        if op == 0x9205:
            print(f"  AF area at {p[0]}, {p[1]}")
            return OK, None
        if op == 0x90C1:
            self.busy_until = now + 0.3
            return OK, None
        if op in (0x9207, 0x100E, 0x90C0):
            if now < self.busy_until:
                return BUSY, None
            shutter = self.props[self.shutter_code].value
            if shutter >= 0xFFFFFFFC:
                return 0xA200, None
            seconds = shutter_seconds(shutter, not self.dslr)
            for handle in self.add_picture():
                self.events.append((0x4002, handle))
            self.events.append((0x400D, 0))
            self.busy_until = now + seconds + 0.5
            return OK, None
        if op == 0x920A:
            self.recording = True
            print("  recording")
            return OK, None
        if op == 0x920B:
            if self.recording:
                for handle in self.add_picture(movie=True):
                    self.events.append((0x4002, handle))
            self.recording = False
            print("  stopped recording")
            return OK, None
        if op == 0x90C7:
            events, self.events = self.events, []
            return OK, struct.pack("<H", len(events)) + b"".join(struct.pack("<HI", c, v) for c, v in events)
        if op == 0x941C:
            events, self.events = self.events, []
            body = b"".join(struct.pack("<HHI", c, 1, v) for c, v in events)
            return OK, struct.pack("<HH", len(events), 0) + body
        if op == 0x1004:
            return OK, u32_array([STORAGE])
        if op == 0x1007:
            return OK, u32_array(sorted(self.objects))
        if op == 0x1008:
            return (OK, self.object_info(p[0])) if p[0] in self.objects else (0x2009, None)
        if op in (0x100A, 0x90C4):
            o = self.objects.get(p[0])
            if o is None or o["folder"]:
                return 0x2009, None
            return OK, o["jpeg"]
        if op == 0x1009:
            o = self.objects.get(p[0])
            return (OK, o["data"]) if o else (0x2009, None)
        if op == 0x101B:
            o = self.objects.get(p[0])
            if o is None:
                return 0x2009, None
            return OK, o["data"][p[1]:p[1] + p[2]]
        return NOT_SUPPORTED, None


# ---- PTP/IP server ---------------------------------------------------------------------------

def read_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("closed")
        data += chunk
    return data


def read_packet(sock):
    length, ptype = struct.unpack("<II", read_exact(sock, 8))
    return ptype, read_exact(sock, length - 8)


class Handler(socketserver.BaseRequestHandler):
    cam = None
    connections = 0

    def handle(self):
        sock = self.request
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        try:
            ptype, payload = read_packet(sock)
            if ptype == 1:
                self.command_channel(sock, payload)
            elif ptype == 3:
                print("event channel open")
                sock.sendall(packet(4))
                while True:   # Nikon delivers events by polling; just keep the channel open.
                    ptype, _ = read_packet(sock)
                    if ptype == 13:
                        sock.sendall(packet(14))
            else:
                print(f"unexpected first packet type {ptype}")
        except (ConnectionError, OSError):
            pass

    def command_channel(self, sock, payload):
        cam = self.cam
        name = payload[16:-4].decode("utf-16-le", "replace").rstrip("\x00")
        Handler.connections += 1
        print(f"PTP/IP: {name!r} connected (GUID {payload[:16].hex()})")
        ack = struct.pack("<I", Handler.connections) + bytes(range(16)) + (cam.model + "\x00").encode("utf-16-le")
        sock.sendall(packet(2, ack + struct.pack("<I", 0x00010000)))
        try:
            while True:
                ptype, body = read_packet(sock)
                if ptype == 13:
                    sock.sendall(packet(14))
                    continue
                if ptype != 6:
                    continue
                phase, op, tid = struct.unpack("<IHI", body[:10])
                params = list(struct.unpack(f"<{(len(body) - 10) // 4}I", body[10:10 + 4 * ((len(body) - 10) // 4)]))
                data_out = None
                if phase == 2:
                    data_out = b""
                    while True:
                        dtype, dbody = read_packet(sock)
                        if dtype in (10, 12):
                            data_out += dbody[4:]
                        if dtype == 12:
                            break
                with cam.lock:
                    code, data_in = cam.operation(op, params, data_out)
                if op not in (0x9203, 0x90C8, 0x1014, 0x941C, 0x90C7, 0x100A) or code not in (OK, BUSY):
                    print(f"op {op:#06x} {' '.join(hex(x) for x in params)} -> {code:#06x}"
                          + (f" ({len(data_in)} bytes)" if data_in else ""))
                if data_in is not None:
                    sock.sendall(packet(9, struct.pack("<IQ", tid, len(data_in))))
                    chunks = [data_in[i:i + 65536] for i in range(0, len(data_in), 65536)] or [b""]
                    for chunk in chunks[:-1]:
                        sock.sendall(packet(10, struct.pack("<I", tid) + chunk))
                    sock.sendall(packet(12, struct.pack("<I", tid) + chunks[-1]))
                sock.sendall(packet(7, struct.pack("<HI", code, tid)))
        finally:
            with cam.lock:
                cam.session = False
                cam.live_view = False
            print("PTP/IP: command channel closed")


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bind", default="127.0.0.1", help="address to listen on (default 127.0.0.1)")
    ap.add_argument("--port", type=int, default=15740, help="PTP/IP port (default 15740, as on the camera)")
    ap.add_argument("--dslr", action="store_true", help="behave like a D750 instead of a Z 6II")
    args = ap.parse_args()
    sys.stdout.reconfigure(line_buffering=True)
    cam = MockNikon(load_frames(), dslr=args.dslr)
    Handler.cam = cam
    server = Server((args.bind, args.port), Handler)
    print(f"Mock Nikon {cam.model} (PTP/IP) on {args.bind}:{args.port} ({len(cam.frames)} frames, "
          f"{sum(1 for o in cam.objects.values() if not o['folder'])} files on card)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    sys.exit(main())
