#!/usr/bin/env python3
"""
Mock Olympus PEN-F for testing Shutterlink without the camera.

It speaks the same OI.Share Wi-Fi protocol as the real body: HTTP commands
(switch_cammode, get_camprop, set_camprop, exec_takemotion, get_imglist, ...)
and RTP/UDP JPEG live view sent back to whoever asked for it.

    python3 mock_penf.py                 # listens on 127.0.0.1:8080
    python3 mock_penf.py --bind 0.0.0.0  # reachable from a real iPhone on your Wi-Fi

In the app: Connect screen > Advanced > Camera address = 127.0.0.1:8080
(Simulator) or <this Mac's IP>:8080 (iPhone on the same network).

Like the real camera it is strict about modes: live view, shooting and settings
need "rec" mode, the card browser needs "play" mode. Wrong mode -> HTTP 520.
"""
import argparse
import datetime
import random
import re
import socket
import struct
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qsl, urlsplit

HERE = Path(__file__).resolve().parent
FRAMES_DIR = HERE / "frames"
ACCEPTED_USER_AGENTS = {"OI.Share v2", "OlympusCameraKit"}
FPS = 20

SHUTTER = ['livecomp', 'livetime', 'livebulb', '60"', '50"', '40"', '30"', '25"', '20"', '15"', '13"', '10"', '8"', '6"', '5"', '4"',
           '3.2"', '2.5"', '2"', '1.6"', '1.3"', '1"', '1.3', '1.6', '2', '2.5', '3', '4', '5', '6',
           '8', '10', '13', '15', '20', '25', '30', '40', '50', '60', '80', '100', '125', '160',
           '200', '250', '320', '400', '500', '640', '800', '1000', '1250', '1600', '2000',
           '2500', '3200', '4000', '5000', '6400', '8000']
APERTURE = ['1.8', '2.0', '2.2', '2.5', '2.8', '3.2', '3.5', '4.0', '4.5', '5.0', '5.6', '6.3',
            '7.1', '8.0', '9.0', '10', '11', '13', '14', '16', '18', '20', '22']
ISO = ['Auto', 'Low', '200', '250', '320', '400', '500', '640', '800', '1000', '1250', '1600',
       '2000', '2500', '3200', '4000', '5000', '6400', '8000', '10000', '12800', '16000',
       '20000', '25600']
EV = ["0.0" if i == 0 else f"{i / 3:+.1f}" for i in range(-15, 16)]
WB = ['0', '18', '16', '17', '20', '35', '64', '23', '256', '257', '258', '259', '512']
DRIVE = ['normal', 'lowvib-normal', 'silent-normal', 'continuous-H', 'silent-continuous-H',
         'continuous-L', 'lowvib-continuous-L', 'silent-continuous-L', 'selftimer',
         'lowvib-selftimer', 'silent-selftimer', 'customselftimer']
ART = ['popart', 'fantasic_focus', 'daydream', 'light_tone', 'rough_monochrome', 'toy_photo',
       'miniature', 'cross_process', 'gentle_sepia', 'dramatic_tone', 'ligne_clair', 'pastel',
       'vintage', 'partcolor']
TAKEMODE = ['iAuto', 'P', 'A', 'S', 'M', 'ART', 'movie']
COLORTONE = ['i_finish', 'vivid', 'natural', 'flat', 'portrait', 'monotone', 'custom',
             'e_portrait', 'color_creator']

ENUMS = {
    'takemode': TAKEMODE, 'drivemode': DRIVE, 'focalvalue': APERTURE, 'expcomp': EV,
    'shutspeedvalue': SHUTTER, 'isospeedvalue': ISO, 'wbvalue': WB, 'artfilter': ART,
    'colortone': COLORTONE,
}

# Like the real list it also offers exec_shutter (not served here): bodies with starttake must still use it.
COMMAND_LIST = """<?xml version="1.0" encoding="Shift-JIS"?>
<oishare>
 <version>mock-1.0</version>
 <support func="web"/>
 <support func="remote"/>
 <support func="release"/>
 <cgi name="get_connectmode"><http_method type="get"/></cgi>
 <cgi name="get_caminfo"><http_method type="get"/></cgi>
 <cgi name="exec_pwoff"><http_method type="get"/></cgi>
 <cgi name="switch_cammode">
  <http_method type="get">
   <cmd1 name="mode">
    <param1 name="rec">
     <cmd2 name="lvqty">
      <param2 name="0320x0240"/><param2 name="0640x0480"/><param2 name="0800x0600"/>
      <param2 name="1024x0768"/><param2 name="1280x0960"/>
     </cmd2>
    </param1>
    <param1 name="play"/>
    <param1 name="shutter"/>
   </cmd1>
  </http_method>
 </cgi>
 <cgi name="exec_takemotion">
  <http_method type="get">
   <cmd1 name="com">
    <param1 name="assignafframe"><cmd2 name="point"/></param1>
    <param1 name="releaseafframe"/>
    <param1 name="takeready"><cmd2 name="point"/></param1>
    <param1 name="starttake"><cmd2 name="point"><cmd3 name="exposuremin"/><cmd3 name="upperlimit"/></cmd2></param1>
    <param1 name="stoptake"/>
    <param1 name="startmovietake"/>
    <param1 name="stopmovietake"/>
   </cmd1>
  </http_method>
 </cgi>
 <cgi name="exec_takemisc">
  <http_method type="get">
   <cmd1 name="com">
    <param1 name="startliveview"><cmd2 name="port"/></param1>
    <param1 name="stopliveview"/>
    <param1 name="getrecview"/>
    <param1 name="getlastjpg"/>
   </cmd1>
  </http_method>
 </cgi>
 <cgi name="exec_shutter">
  <http_method type="get">
   <cmd1 name="com">
    <param1 name="1stpush"/><param1 name="2ndpush"/><param1 name="1st2ndpush"/>
    <param1 name="2nd1strelease"/><param1 name="2ndrelease"/><param1 name="1strelease"/>
   </cmd1>
  </http_method>
 </cgi>
 <cgi name="get_camprop"><http_method type="get"/></cgi>
 <cgi name="set_camprop"><http_method type="post"/></cgi>
 <cgi name="get_imglist"><http_method type="get"/></cgi>
 <cgi name="set_utctimediff"><http_method type="get"/></cgi>
 <cgi name="get_thumbnail"><http_method type="get"/></cgi>
 <cgi name="get_resizeimg"><http_method type="get"/></cgi>
</oishare>
"""


def load_frames():
    if not any(FRAMES_DIR.glob("*.jpg")):
        print("Rendering live-view frames (first run only)...")
        subprocess.run(["swift", str(HERE / "make_frames.swift"), str(FRAMES_DIR)], check=True)
    return [p.read_bytes() for p in sorted(FRAMES_DIR.glob("*.jpg"))]


# ---- shared by all the mocks ------------------------------------------------------------------

class QuietHandler(BaseHTTPRequestHandler):
    """Keep-alive HTTP/1.1 like the cameras, without the default per-request log line."""
    protocol_version = "HTTP/1.1"
    content_type = "text/xml"

    def log_message(self, fmt, *args):
        pass

    def reply(self, status=200, body=b"", ctype=None):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        if body:
            self.send_header("Content-Type", ctype or self.content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def arguments(doc, port, real_port):
    """--bind and --port, which every mock has; each adds its own flags before parse_args()."""
    sys.stdout.reconfigure(line_buffering=True)
    ap = argparse.ArgumentParser(description=doc, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bind", default="127.0.0.1", help="address to listen on (default 127.0.0.1)")
    ap.add_argument("--port", type=int, default=port, help=f"port (default {port}; the real camera uses {real_port})")
    return ap


def serve(server, background=False):
    """Serves until Ctrl-C, or on a daemon thread (a mock's extra ports)."""
    if background:
        return threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


# ---- PEN-F -----------------------------------------------------------------------------------

def fat_datetime(dt):
    d = ((dt.year - 1980) << 9) | (dt.month << 5) | dt.day
    t = (dt.hour << 11) | (dt.minute << 5) | (dt.second // 2)
    return d, t


def shutter_fraction(value):
    if value.endswith('"'):
        secs = float(value[:-1])
        return (int(round(secs * 10)), 10) if secs != int(secs) else (int(secs), 1)
    try:
        denom = float(value)
    except ValueError:
        return (1, 60)
    return (10, int(round(denom * 10))) if denom != int(denom) else (1, int(denom))


class MockCamera:
    def __init__(self, frames):
        self.lock = threading.RLock()
        self.frames = frames
        self.frame_index = 0
        self.mode = "play"
        self.lvqty = "0640x0480"
        self.lv_target = None
        self.af = None  # (state, x, y, w, h, expires_at)
        self.counter = 1
        self.values = {
            'takemode': 'P', 'drivemode': 'normal', 'focalvalue': '5.6', 'expcomp': '0.0',
            'shutspeedvalue': '250', 'isospeedvalue': 'Auto', 'wbvalue': '0',
            'artfilter': 'popart', 'colortone': 'natural',
        }
        self.images = []
        self.open_since = None   # Live Composite / Time / Bulb exposure in progress
        start = datetime.datetime.now() - datetime.timedelta(days=2)
        for k in range(6):
            # Every other one was shot RAW+JPEG, so the card has .ORF files next to some JPEGs.
            self.add_image(frames[(k * 13) % len(frames)], start + datetime.timedelta(hours=k * 5), raw=(k % 2 == 0))

    # -- state helpers -------------------------------------------------------
    def add_image(self, data, when=None, raw=True):
        """Adds a JPEG, and with raw=True an .ORF beside it (the camera set to RAW+JPEG)."""
        when = when or datetime.datetime.now()
        month = "123456789ABC"[when.month - 1]
        base = f"P{month}{when.day:02d}{self.counter:04d}"
        self.counter += 1
        self.images.append((base + ".JPG", data, when))
        if raw:
            # Not a real ORF (just bytes of a plausible size), so Photos will refuse it: the app
            # then saves it to Files instead, which is what this lets you test.
            fake = b"IIRO" + random.Random(base).randbytes(1_500_000)
            self.images.append((base + ".ORF", fake, when))
        return base + ".JPG"

    def attribute(self, name):
        mode = self.values['takemode']
        if name == 'focalvalue':
            return 'getset' if mode in ('A', 'M') else 'get'
        if name == 'shutspeedvalue':
            return 'getset' if mode in ('S', 'M') else 'get'
        if name == 'expcomp':
            return 'get' if mode in ('M', 'iAuto') else 'getset'
        if name == 'artfilter':
            return 'getset' if mode == 'ART' else 'get'
        if mode == 'iAuto' and name in ('isospeedvalue', 'wbvalue', 'colortone'):
            return 'get'
        return 'getset'

    def desclist(self):
        parts = ['<?xml version="1.0" encoding="Shift-JIS"?>', '<desclist>']
        for name, options in ENUMS.items():
            parts.append(f"<desc><propname>{name}</propname><attribute>{self.attribute(name)}</attribute>"
                         f"<value>{self.values[name]}</value><enum>{' '.join(options)}</enum></desc>")
        parts.append('</desclist>')
        return "\n".join(parts)

    def extension(self, jpeg_size):
        def field(fid, *words):
            return struct.pack(">HH", fid, len(words)) + b"".join(
                struct.pack(">i" if w < 0 else ">I", w) for w in words)

        af = self.af if self.af and self.af[5] > time.time() else None
        num, den = shutter_fraction(self.values['shutspeedvalue'])
        iso = self.values['isospeedvalue']
        iso_value, auto = (400, 1) if iso == 'Auto' else ((0xFFFE, 0) if iso == 'Low' else (int(iso), 0))
        ev = int(round(float(self.values['expcomp']) * 10))
        return b"".join([
            field(1, jpeg_size),
            field(2, *(af[:5] if af else (0, 0, 0, 0, 0))),
            field(4, 1),
            field(8, 60, 1, 1, 8000, num, den),
            field(9, 220, 18, int(round(float(self.values['focalvalue']) * 10))),
            field(10, 50, -50, ev),
            field(12, iso_value, auto << 16, 0),
            field(5, max(0, 4406 - len(self.images))),   # shots remaining
            field(6, 0),                                  # temperature warning
            field(7, 72),                                 # battery %
            field(14, (4 << 16) | 3),                     # aspect 4:3
            field(18, (8 << 16) | 30, (30 << 16) | 30, 0),  # focal length 30 mm
        ])


def live_view_loop(cam):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    ssrc = random.getrandbits(32)
    seq = 0
    timestamp = 0
    chunk = 1400
    while True:
        started = time.time()
        with cam.lock:
            target = cam.lv_target
            jpeg = cam.frames[cam.frame_index % len(cam.frames)]
            cam.frame_index += 1
            ext = cam.extension(len(jpeg)) if target else b""
        if target:
            pieces = [jpeg[i:i + chunk] for i in range(0, len(jpeg), chunk)]
            for i, piece in enumerate(pieces):
                first, last = i == 0, i == len(pieces) - 1
                b0 = 0x80 | (0x10 if first else 0)
                b1 = (0x80 if last else 0) | 96
                header = struct.pack(">BBHII", b0, b1, seq & 0xFFFF, timestamp & 0xFFFFFFFF, ssrc)
                if first:
                    header += struct.pack(">HH", 1, len(ext) // 4) + ext
                try:
                    sock.sendto(header + piece, target)
                except OSError as e:
                    print(f"  ! UDP send to {target} failed: {e}")
                    break
                seq += 1
            timestamp += 1
        time.sleep(max(0.0, 1.0 / FPS - (time.time() - started)))


class Handler(QuietHandler):
    busy = 0
    cam: MockCamera = None
    model = "PEN-F"

    def refuse(self, why):
        print(f"  ! refused: {why}")
        self.reply(520, '<?xml version="1.0"?><response><errorcode>0xB000</errorcode>'
                        f'<errormsg>WIFI_INTERNAL_ERROR</errormsg><dbgmsg>{why}</dbgmsg></response>')

    def xml(self, body):
        self.reply(200, '<?xml version="1.0"?>' + body)

    # -- dispatch -------------------------------------------------------------
    def handle_request(self):
        cam = self.cam
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        parts = urlsplit(self.path)
        query = dict(parse_qsl(parts.query, keep_blank_values=True))
        ua = self.headers.get("User-Agent", "")
        print(f"{self.command} {self.path}   [mode={cam.mode}] ua={ua!r}")

        if not self.headers.get("Host"):
            return self.reply(400)
        if ua not in ACCEPTED_USER_AGENTS:
            return self.refuse(f"unexpected User-Agent {ua!r}")

        path = parts.path
        if path.upper().startswith("/DCIM/"):
            return self.file(path)
        if not path.endswith(".cgi"):
            return self.reply(404)
        command = path[1:-4]
        handler = getattr(self, "cmd_" + command, None)
        if handler is None:
            return self.reply(404)
        with cam.lock:
            handler(query, body)

    do_GET = do_POST = handle_request

    # -- commands -------------------------------------------------------------
    def cmd_get_connectmode(self, q, body):
        self.xml("<connectmode>private</connectmode>")

    def cmd_get_caminfo(self, q, body):
        self.xml(f"<caminfo><model>{self.model} (mock)</model></caminfo>")

    def cmd_get_commandlist(self, q, body):
        self.reply(200, COMMAND_LIST)

    def cmd_switch_cammode(self, q, body):
        mode = q.get("mode")
        if mode not in ("rec", "play"):
            return self.reply(400)
        self.cam.mode = mode
        if mode != "rec":
            self.cam.lv_target = None
        if "lvqty" in q:
            self.cam.lvqty = q["lvqty"]
        self.reply(200)

    def cmd_exec_takemisc(self, q, body):
        com = q.get("com")
        if com == "startliveview":
            if self.cam.mode != "rec":
                return self.refuse("live view needs rec mode")
            self.cam.lv_target = (self.client_address[0], int(q.get("port", "0")))
            print(f"  live view -> udp://{self.cam.lv_target[0]}:{self.cam.lv_target[1]}")
            return self.reply(200)
        if com == "stopliveview":
            self.cam.lv_target = None
            return self.reply(200)
        if com in ("getrecview", "getlastjpg"):
            if not self.cam.images:
                return self.reply(404)
            last_jpeg = next(data for name, data, _ in reversed(self.cam.images) if name.endswith(".JPG"))
            return self.reply(200, last_jpeg, "image/jpeg")
        self.reply(200)

    def parse_point(self, q):
        m = re.fullmatch(r"(\d{4})x(\d{4})", q.get("point", ""))
        return (int(m.group(1)), int(m.group(2))) if m else None

    def cmd_exec_takemotion(self, q, body):
        cam = self.cam
        com = q.get("com")
        if cam.mode != "rec":
            return self.refuse("shooting needs rec mode")
        point = self.parse_point(q)
        if com in ("assignafframe", "takeready"):
            if not point:
                return self.reply(400)
            x, y = point
            ok = random.random() > 0.15
            cam.af = (1 if ok else 2, max(0, x - 40), max(0, y - 30), 80, 60, time.time() + 4)
            return self.xml(f"<response><affocus>{'ok' if ok else 'ng'}</affocus>"
                            f"<afframepoint>{x - 40:04d}x{y - 30:04d}</afframepoint>"
                            "<afframesize>0080x0060</afframesize></response>")
        if com == "releaseafframe":
            cam.af = None
            return self.reply(200)
        if com == "starttake":
            if point:
                cam.af = (1, max(0, point[0] - 40), max(0, point[1] - 30), 80, 60, time.time() + 2)
            if cam.values['shutspeedvalue'] in ('livecomp', 'livetime', 'livebulb'):
                cam.open_since = time.time()
                print(f"  * {cam.values['shutspeedvalue']} exposure started")
                return self.xml("<response><take>ok</take></response>")
            time.sleep(0.35)  # pretend to focus and expose
            cam.busy_until = time.time() + Handler.busy  # still writing the file, like a real body with RAW
            name = cam.add_image(cam.frames[cam.frame_index % len(cam.frames)])
            print(f"  * click -> {name}")
            return self.xml("<response><take>ok</take><affocus>ok</affocus></response>")
        if com == "startmovietake":
            cam.movie_started = time.time()
            print("  * movie recording started")
            return self.reply(200)
        if com == "stopmovietake":
            started = getattr(cam, "movie_started", None)
            if started:
                cam.images.append((f"P{cam.counter:07d}.MOV", cam.frames[0], datetime.datetime.now()))
                cam.counter += 1
                print(f"  * movie stopped after {time.time() - started:.1f}s")
                cam.movie_started = None
            return self.reply(200)
        if com == "stoptake":
            if cam.open_since is not None:
                seconds = time.time() - cam.open_since
                cam.open_since = None
                name = cam.add_image(cam.frames[cam.frame_index % len(cam.frames)])
                print(f"  * {cam.values['shutspeedvalue']} stopped after {seconds:.1f}s -> {name}")
            return self.reply(200)
        self.reply(200)

    def cmd_get_camprop(self, q, body):
        cam = self.cam
        if cam.mode != "rec":
            return self.refuse("settings need rec mode")
        com, name = q.get("com"), q.get("propname")
        if com == "desc" and name == "desclist":
            return self.reply(200, cam.desclist())
        self.reply(400)

    def cmd_set_camprop(self, q, body):
        cam = self.cam
        if cam.mode != "rec":
            return self.refuse("settings need rec mode")
        if time.time() < getattr(cam, "busy_until", 0):
            return self.refuse("busy writing the last shot")
        name = q.get("propname")
        m = re.search(rb"<value>(.*?)</value>", body, re.S)
        if not m or name not in cam.values:
            return self.reply(400)
        value = m.group(1).decode().strip()
        if cam.attribute(name) != "getset":
            return self.refuse(f"{name} is read-only in {cam.values['takemode']} mode")
        if value not in ENUMS[name]:
            return self.refuse(f"{value!r} is not a valid {name}")
        cam.values[name] = value
        print(f"  set {name} = {value}")
        self.reply(200)

    def cmd_get_imglist(self, q, body):
        cam = self.cam
        if cam.mode != "play":
            return self.refuse("card browsing needs play mode")
        d = q.get("DIR", "").rstrip("/")
        if d == "/DCIM":
            date, tm = fat_datetime(datetime.datetime.now())
            return self.reply(200, f"VER_100\r\n/DCIM,116_PANA,0,16,{date},{tm}\r\n/DCIM,100OLYMP,0,16,{date},{tm}\r\n", "text/plain")
        if d == "/DCIM/116_PANA":
            # Like the real PEN-F: another camera's folder is listed as empty.
            return self.reply(200, "VER_100\r\n", "text/plain")
        if d == "/DCIM/100OLYMP" and cam.images:
            lines = ["VER_100"]
            for name, data, when in cam.images:
                date, tm = fat_datetime(when)
                lines.append(f"/DCIM/100OLYMP,{name},{len(data)},0,{date},{tm}")
            return self.reply(200, "\r\n".join(lines) + "\r\n", "text/plain")
        self.reply(404)

    def find_image(self, path):
        name = path.rsplit("/", 1)[-1]
        for n, data, _ in self.cam.images:
            if n == name:
                return data
        return None

    def cmd_get_thumbnail(self, q, body):
        if self.cam.mode != "play":
            return self.refuse("thumbnails need play mode")
        path = q.get("DIR", "")
        if path.upper().endswith(".ORF"):
            path = path[:-4] + ".JPG"   # the camera shows a RAW's embedded preview
        data = self.find_image(path)
        self.reply(200, data, "image/jpeg") if data else self.reply(404)

    cmd_get_resizeimg = cmd_get_thumbnail

    def file(self, path):
        data = self.find_image(path)
        ctype = "application/octet-stream" if path.upper().endswith(".ORF") else "image/jpeg"
        self.reply(200, data, ctype) if data else self.reply(404)

    def cmd_set_utctimediff(self, q, body):
        if self.cam.mode != "play":
            return self.refuse("clock sync needs play mode")
        print(f"  clock set to {q.get('utctime')} UTC, offset {q.get('diff')}")
        self.reply(200)

    def cmd_exec_pwoff(self, q, body):
        self.cam.lv_target = None
        print("  (camera would power off now)")
        self.reply(202)


def main():
    ap = arguments(__doc__, 8080, 80)
    ap.add_argument("--model", default="PEN-F",
                    help="model name get_caminfo reports, e.g. E-M10MarkIII or AIR-A01 (default PEN-F)")
    ap.add_argument("--busy", type=float, default=0,
                    help="seconds after each shot during which settings are refused with 520, like a real body "
                         "that is still writing the file (default 0)")
    args = ap.parse_args()
    cam = MockCamera(load_frames())
    Handler.cam, Handler.model, Handler.busy = cam, args.model, args.busy
    threading.Thread(target=live_view_loop, args=(cam,), daemon=True).start()
    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"Mock PEN-F listening on http://{args.bind}:{args.port}  ({len(cam.frames)} frames, {FPS} fps)")
    serve(server)


if __name__ == "__main__":
    sys.exit(main())
