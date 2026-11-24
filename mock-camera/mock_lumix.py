#!/usr/bin/env python3
"""
Mock Panasonic LUMIX GH5 for testing Shutterlink's LUMIX support without the camera.

It speaks the Image App / LUMIX Sync Wi-Fi protocol as described by open-source
implementations (the real GH5 has not been checked against this):

  * cam.cgi commands on HTTP (the real camera uses port 80 at 192.168.54.1):
    pairing (accctrl req_acc), getstate, getinfo, getsetting/setsetting,
    camcmd (recmode, playmode, capture, video, poweroff), camctrl touch AF and focus drive,
    startstream/stopstream.
  * Live view over UDP: one JPEG per datagram after a 32-byte header whose
    bytes 30-31 give the length of an extra header that follows it.
  * A UPnP ContentDirectory on port 60606 (needs play mode) listing the card,
    and the files themselves on port 50001.

    python3 mock_lumix.py                 # cam.cgi on 127.0.0.1:8082
    python3 mock_lumix.py --bind 0.0.0.0  # reachable from a real iPhone on your Wi-Fi

In the app: Connect screen > LUMIX > Advanced > Camera address = 127.0.0.1:8082.

Like the real camera it asks before letting a new phone in: the first two
pairing requests answer "ok_under_research" (the camera is showing its
Yes/No prompt), then it accepts. --refuse makes it say No instead.

--encrypted acts like the newer bodies (S5IIX, G9II…) as liblumix describes them:
the UPnP description advertises X_CamCapability ending in 1, pairing is
req_acc_g then req_acc_e (UDN and name as lowercase hex), and every later
cam.cgi request must carry the session id in an X-SESSION_ID header.
It also stops streaming if the app stops polling getstate for 10 seconds.
"""
import argparse
import datetime
import math
import os
import random
import socket
import struct
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qsl, urlsplit
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mock_penf import load_frames  # noqa: E402  (same live-view frames as the PEN-F mock)

UPNP_PORT = 60606
FILE_PORT = 50001
NAME = "GH5-MOCK"
MODEL = "DC-GH5"   # --model changes it, e.g. DC-LX100 or DMC-GH4
UDN = "4D454930-0000-1000-8000-mockgh5"
SESSION = "5e55i0n1d"
ENCRYPTED = False

# A Leica DG 12-60mm f/2.8-4 at the wide end would report a range; keep it simple with a
# 25mm f/1.7 prime: F1.7-F16, 1/8000-60 s. Codes are APEX x 256.
LENS_MIN_F = 1.7
LENS_MAX_F = 16.0
FASTEST = 3328     # 1/8000 s
SLOWEST = -1536    # 60 s
BULB = 16384

ISO = ["auto", "i_iso", "100", "125", "160", "200", "250", "320", "400", "500", "640", "800",
       "1000", "1250", "1600", "2000", "2500", "3200", "4000", "5000", "6400", "8000", "10000",
       "12800", "16000", "20000", "25600"]
WB = ["auto", "daylight", "cloudy", "shade", "flash", "incandescent", "white_set1", "white_set2",
      "white_set3", "white_set4", "color_temp1"]
EXPOSURE = [("0" if t == 0 else (f"{t // 3}" if t % 3 == 0 else f"{t}/3")) for t in range(-15, 16)]


def av_code(f):
    return int(round(2 * math.log2(f) * 256))


def f_from_code(code):
    return 2 ** (code / 512)


def tv_seconds(code):
    return 2 ** (-code / 256)


def code_text(code):
    return f"{code}/256"


def parse_code(text):
    try:
        if "/" in text:
            a, b = text.split("/", 1)
            return int(round(float(a) * 256 / float(b)))
        return int(text)
    except ValueError:
        return None


def snap_thirds(code):
    """Snap an APEX x 256 code to the nearest third stop."""
    return int(round(round(code * 3 / 256) * 256 / 3))


class MockLumix:
    def __init__(self, frames, refuse=False):
        self.lock = threading.Lock()
        self.frames = frames
        self.frame_index = 0
        self.refuse = refuse
        self.pairing_attempts = {}
        self.paired = set()
        self.mode = "rec"
        self.stream_target = None
        self.stream_size = "vga"
        self.last_poll = time.time()
        self.recording = False
        self.bulb_open_since = None
        self.focal = av_code(2.8)
        self.shutter = snap_thirds(int(round(math.log2(125) * 256)))
        self.iso = "auto"
        self.exposure = "0"
        self.whitebalance = "auto"
        self.touch = None
        self.battery = 3
        self.counter = 1000
        self.images = []   # dicts: id, title, date, jpeg, raw, video
        # Enough files (over 50 entries) that the app has to page through the UPnP listing.
        start = datetime.datetime.now() - datetime.timedelta(days=4)
        for k in range(48):
            self.add_image(start + datetime.timedelta(hours=k * 1.5), raw=(k % 3 != 0))
        self.add_image(start + datetime.timedelta(days=3, hours=12), video=True)

    def add_image(self, when=None, raw=True, video=False):
        self.counter += 1
        image_id = f"{1010000 + self.counter}"
        jpeg = self.frames[(self.counter * 7) % len(self.frames)]
        self.images.append({
            "id": image_id, "title": f"P{self.counter:07d}", "date": when or datetime.datetime.now(),
            "jpeg": jpeg, "raw": raw and not video, "video": video,
        })
        return self.images[-1]["title"]


def stream_loop(cam, fps):
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    # macOS limits datagrams to 9216 bytes unless the send buffer is raised.
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1 << 20)
    stopped_for_silence = False
    while True:
        started = time.time()
        with cam.lock:
            target = cam.stream_target if cam.mode == "rec" else None
            if target and time.time() - cam.last_poll > 10:
                if not stopped_for_silence:
                    print("  ! no getstate for 10 s: live view stops (as on the real camera)")
                stopped_for_silence = True
                target = None
            elif target:
                stopped_for_silence = False
            jpeg = cam.frames[cam.frame_index % len(cam.frames)]
            cam.frame_index += 1
        if target:
            extra = struct.pack(">IIHH", cam.frame_index, int(time.time()), 640, 480)
            header = bytearray(32)
            header[0:2] = b"\x01\x00"
            header[30:32] = struct.pack(">H", len(extra))
            packet = bytes(header) + extra + jpeg
            if len(packet) > 65507:
                print(f"  ! frame too big for one datagram ({len(packet)} bytes); skipped")
            else:
                try:
                    sock.sendto(packet, target)
                except OSError as e:
                    print(f"  ! UDP send to {target} failed: {e}")
        time.sleep(max(0.0, 1.0 / fps - (time.time() - started)))


# ---------------------------------------------------------------------------- cam.cgi

class CamHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    cam: MockLumix = None
    verbose = True

    def log_message(self, fmt, *args):
        pass

    def reply(self, status=200, body=b"", ctype="text/xml"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def result(self, code="ok", extra=""):
        if self.verbose or code != "ok":
            print(f"  -> {code}")
        self.reply(200, f'<?xml version="1.0" encoding="UTF-8"?>\n<camrply><result>{code}</result>{extra}</camrply>')

    def csv(self, text):
        if self.verbose:
            print(f"  -> {text}")
        self.reply(200, text, "text/plain")

    def do_GET(self):
        url = urlsplit(self.path)
        q = dict(parse_qsl(url.query, keep_blank_values=True))
        if url.path != "/cam.cgi":
            return self.reply(404, "not found", "text/plain")
        mode = q.get("mode", "")
        if mode != "getstate" or self.verbose:
            print(f"cam.cgi {url.query}")
        if ENCRYPTED and mode != "accctrl" and self.headers.get("X-SESSION_ID") != SESSION:
            print("  (no or wrong X-SESSION_ID: rejected)")
            return self.result("err_reject")
        handler = getattr(self, "mode_" + mode, None)
        if handler is None:
            return self.result("err_non_support")
        with self.cam.lock:
            handler(q)

    # -- pairing & info --------------------------------------------------------
    def mode_accctrl(self, q):
        cam = self.cam
        if ENCRYPTED:
            return self.encrypted_accctrl(q)
        if q.get("type") != "req_acc":
            return self.result("err_param")
        uuid = q.get("value", "")
        if not uuid.startswith("4D454930-0100-1000-8001-"):
            return self.result("err_unsuitable_app")
        if uuid not in cam.paired:
            attempts = cam.pairing_attempts.get(uuid, 0) + 1
            cam.pairing_attempts[uuid] = attempts
            if attempts <= 2:
                print(f"  (camera shows: Connect to {q.get('value2', '?')}? Yes / No)")
                return self.csv("ok_under_research")
            if cam.refuse:
                cam.pairing_attempts[uuid] = 0
                return self.result("err_user_refused")
            cam.paired.add(uuid)
        self.csv(f"ok,{NAME},remote,encrypted")

    def encrypted_accctrl(self, q):
        cam = self.cam
        kind = q.get("type")
        if kind == "req_acc_g":
            return self.csv("ok,1a2b3c4d")
        if kind != "req_acc_e":
            return self.result("err_unsuitable_app")
        try:
            udn = bytes.fromhex(q.get("value", "")).decode()
            name = bytes.fromhex(q.get("value2", "")).decode()
        except ValueError:
            return self.result("err_param")
        if udn != UDN:
            print(f"  (wrong UDN {udn!r})")
            return self.result("err_param")
        if udn not in cam.paired:
            attempts = cam.pairing_attempts.get(udn, 0) + 1
            cam.pairing_attempts[udn] = attempts
            if attempts <= 2:
                print(f"  (camera shows: Connect to {name}? Yes / No)")
                return self.csv("ok_under_research")
            if cam.refuse:
                cam.pairing_attempts[udn] = 0
                return self.result("err_user_refused")
            cam.paired.add(udn)
        self.csv(f"ok,{NAME},remote,open,{SESSION}")

    def mode_getinfo(self, q):
        kind = q.get("type")
        if kind == "capability":
            return self.result("ok", f"<comm_proto_ver>2.6</comm_proto_ver><product_info><model_name>{MODEL}</model_name>"
                                     "</product_info><camera_type>s</camera_type>")
        if kind == "lens":
            return self.csv(f"ok,{code_text(av_code(LENS_MAX_F))},{code_text(av_code(LENS_MIN_F))},"
                            f"{code_text(FASTEST)},{code_text(SLOWEST)},0,on,25,25,off,0,0")
        if kind == "allmenu":
            items = []
            for t, values in (("iso", ISO), ("whitebalance", WB)):
                for v in values:
                    items.append(f'<item id="menu_item_id_{t}_{v}" func_type="select" cmd_mode="setsetting" '
                                 f'cmd_type="{t}" cmd_value="{v}"/>')
            return self.result("ok", "<menuinfo><mainmenu><photosettings>" + "".join(items) +
                               "</photosettings></mainmenu></menuinfo>")
        if kind == "curmenu":
            return self.result("ok", "<menuinfo/>")
        self.result("err_param")

    def mode_getstate(self, q):
        cam = self.cam
        cam.last_poll = time.time()
        rec = "on" if cam.recording else "off"
        self.result("ok", f"<state><batt>{cam.battery}/3</batt><cammode>{cam.mode}</cammode>"
                          f"<remaincapacity>{2400 - len(cam.images)}</remaincapacity>"
                          "<sdcardstatus>write_enable</sdcardstatus><sd_memory>set</sd_memory>"
                          f"<video_remaincapacity>5400</video_remaincapacity><rec>{rec}</rec>"
                          "<burst_interval_status>off</burst_interval_status><sd_access>off</sd_access>"
                          "<temperature>normal</temperature><lens>normal</lens></state>")

    # -- settings ----------------------------------------------------------------
    def mode_getsetting(self, q):
        cam = self.cam
        kind = q.get("type")
        values = {
            "focal": code_text(cam.focal), "shtrspeed": code_text(cam.shutter), "iso": cam.iso,
            "exposure": cam.exposure, "whitebalance": cam.whitebalance, "liveviewsize": cam.stream_size,
        }
        if kind not in values:
            return self.result("err_param")
        self.result("ok", f'<settingvalue {kind}="{values[kind]}"></settingvalue>')

    def mode_setsetting(self, q):
        cam = self.cam
        kind, value = q.get("type"), q.get("value", "")
        if kind == "device_name":
            print(f"  (phone calls itself {value})")
            return self.result()
        if kind == "liveviewsize":
            if value not in ("vga", "qvga"):
                return self.result("err_param")
            cam.stream_size = value
            return self.result()
        if cam.mode != "rec":
            return self.result("err_reject")
        if kind == "focal":
            code = parse_code(value)
            if code is None:
                return self.result("err_param")
            f = f_from_code(code)
            if f < LENS_MIN_F - 0.05 or f > LENS_MAX_F + 0.05:
                return self.result("err_param")
            cam.focal = code if abs(code - av_code(LENS_MIN_F)) <= 2 else snap_thirds(code)
            print(f"  aperture now F{f_from_code(cam.focal):.1f}")
        elif kind == "shtrspeed":
            code = parse_code(value)
            if code is None:
                return self.result("err_param")
            if code != BULB and not (SLOWEST <= code <= FASTEST):
                return self.result("err_param")
            cam.shutter = code if code == BULB else snap_thirds(code)
            print("  shutter now " + ("Bulb" if code == BULB else f"{tv_seconds(cam.shutter):.5g} s"))
        elif kind == "iso":
            if value not in ISO:
                return self.result("err_param")
            cam.iso = value
        elif kind == "exposure":
            if value not in EXPOSURE:
                return self.result("err_param")
            cam.exposure = value
        elif kind == "whitebalance":
            if value not in WB:
                return self.result("err_param")
            cam.whitebalance = value
        else:
            return self.result("err_param")
        self.result()

    # -- shooting ----------------------------------------------------------------
    def mode_camcmd(self, q):
        cam = self.cam
        value = q.get("value")
        if value == "recmode":
            cam.mode = "rec"
            return self.result()
        if value == "playmode":
            cam.mode = "play"
            cam.stream_target = None
            return self.result()
        if value == "poweroff":
            cam.stream_target = None
            print("  (camera would power off now)")
            return self.result()
        if value == "autoreviewunlock":
            return self.result()
        if cam.mode != "rec":
            return self.result("err_reject")
        if value == "capture":
            if cam.recording:
                return self.result("err_busy")
            if cam.shutter == BULB:
                cam.bulb_open_since = time.time()
                print("  bulb: shutter open")
                return self.result()
            title = cam.add_image()
            print(f"  click -> {title}")
            return self.result()
        if value == "capture_cancel":
            if cam.bulb_open_since is not None:
                seconds = time.time() - cam.bulb_open_since
                cam.bulb_open_since = None
                title = cam.add_image()
                print(f"  bulb closed after {seconds:.1f} s -> {title}")
            return self.result()
        if value == "video_recstart":
            cam.recording = True
            print("  recording video")
            return self.result()
        if value == "video_recstop":
            if cam.recording:
                cam.recording = False
                title = cam.add_image(video=True)
                print(f"  video saved -> {title}")
            return self.result()
        self.result("err_param")

    def mode_camctrl(self, q):
        cam = self.cam
        if q.get("type") == "focus":
            # Manual focus drive: wide-* nearer, tele-* farther; "-fast" moves 8x as far.
            # Replies "ok,<position>,<end>" as plain text (not XML), like the real cameras.
            steps = {"wide-normal": -8, "wide-fast": -64, "tele-normal": 8, "tele-fast": 64}
            value = q.get("value", "")
            if value not in steps:
                return self.result("err_param")
            cam.focus_pos = max(0, min(1024, getattr(cam, "focus_pos", 200) + steps[value]))
            print(f"  focus {value} -> {cam.focus_pos}/1024")
            return self.reply(200, f"ok,{cam.focus_pos},1024", "text/plain")
        if q.get("type") != "touch":
            return self.result("err_param")
        if q.get("value2") == "off":
            cam.touch = None
            return self.result()
        try:
            x, y = (int(v) for v in q.get("value", "").split("/"))
        except ValueError:
            return self.result("err_param")
        if not (0 <= x <= 1000 and 0 <= y <= 1000):
            return self.result("err_param")
        cam.touch = (x, y)
        print(f"  focus at {x}/{y} (of 1000)")
        self.result()

    def mode_startstream(self, q):
        cam = self.cam
        if cam.mode != "rec":
            return self.result("err_reject")
        try:
            port = int(q.get("value", ""))
        except ValueError:
            return self.result("err_param")
        cam.stream_target = (self.client_address[0], port)
        cam.last_poll = time.time()
        print(f"  streaming {cam.stream_size} to {cam.stream_target}")
        self.result()

    def mode_stopstream(self, q):
        self.cam.stream_target = None
        self.result()


# ---------------------------------------------------------------------------- UPnP + files

DEVICE_DESCRIPTION = """<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:pana="urn:schemas-panasonic-com:pana">
<specVersion><major>1</major><minor>0</minor></specVersion>
<device>
<deviceType>urn:schemas-upnp-org:device:MediaServer:1</deviceType>
<friendlyName>{name}</friendlyName>
<manufacturer>Panasonic</manufacturer>
<modelName>LUMIX</modelName>
<modelNumber>{model}</modelNumber>
<UDN>uuid:{udn}</UDN>{capability}
<serviceList>
<service>
<serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
<serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
<SCPDURL>/Server0/CMS_SCPD</SCPDURL>
<controlURL>/Server0/CMS_control</controlURL>
<eventSubURL>/Server0/CMS_event</eventSubURL>
</service>
<service>
<serviceType>urn:schemas-upnp-org:service:ContentDirectory:1</serviceType>
<serviceId>urn:upnp-org:serviceId:ContentDirectory</serviceId>
<SCPDURL>/Server0/CDS_SCPD</SCPDURL>
<controlURL>/Server0/CDS_control</controlURL>
<eventSubURL>/Server0/CDS_event</eventSubURL>
</service>
</serviceList>
</device>
</root>
"""


class MediaHandler(BaseHTTPRequestHandler):
    """Port 60606 (UPnP) and 50001 (files) share this handler; the port decides which paths exist."""
    protocol_version = "HTTP/1.1"
    cam: MockLumix = None

    def log_message(self, fmt, *args):
        pass

    def reply(self, status, body=b"", ctype="text/xml; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    @property
    def host_ip(self):
        return (self.headers.get("Host") or "127.0.0.1").split(":")[0]

    def do_GET(self):
        port = self.server.server_address[1]
        path = urlsplit(self.path).path
        if port == UPNP_PORT:
            if path == "/Server0/ddd":
                print("UPnP: device description")
                capability = "\n<pana:X_CamCapability>0001</pana:X_CamCapability>" if ENCRYPTED else ""
                return self.reply(200, DEVICE_DESCRIPTION.format(name=NAME, udn=UDN, capability=capability, model=MODEL))
            return self.reply(404, "not found", "text/plain")
        # File server: /DO<id>.JPG original, /DO<id>.RW2 raw, /DT thumbnail, /DL large preview.
        name = path.lstrip("/")
        kind, rest = name[:2], name[2:]
        image_id, _, ext = rest.partition(".")
        with self.cam.lock:
            image = next((i for i in self.cam.images if i["id"] == image_id), None)
        if image is None or kind not in ("DO", "DT", "DL"):
            print(f"file: {path} -> 404")
            return self.reply(404, "not found", "text/plain")
        if kind == "DO" and ext.upper() == "RW2":
            # Not a real RW2: random bytes of a plausible size so downloads take a moment.
            body, ctype = random.Random(image_id).randbytes(4_000_000), "application/octet-stream"
        elif kind == "DO" and ext.upper() == "MP4":
            body, ctype = random.Random(image_id).randbytes(2_000_000), "video/mp4"
        else:
            body, ctype = image["jpeg"], "image/jpeg"
        print(f"file: {path} ({len(body)} bytes)")
        self.reply(200, body, ctype)

    def do_POST(self):
        port = self.server.server_address[1]
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8", "replace")
        if port != UPNP_PORT or urlsplit(self.path).path != "/Server0/CDS_control":
            return self.reply(404, "not found", "text/plain")
        if "Browse" not in (self.headers.get("SOAPACTION") or ""):
            return self.reply(500, soap_fault(401, "Invalid Action"))

        def field(tag, default=""):
            start = body.find(f"<{tag}>")
            end = body.find(f"</{tag}>")
            return body[start + len(tag) + 2:end].strip() if start >= 0 and end > start else default

        object_id = field("ObjectID", "0")
        start = int(field("StartingIndex", "0") or 0)
        count = int(field("RequestedCount", "50") or 50) or 50
        with self.cam.lock:
            if self.cam.mode != "play":
                print("UPnP Browse refused: camera is in rec mode")
                return self.reply(500, soap_fault(720, "Cannot process the request (not in playback mode)"))
            images = sorted(self.cam.images, key=lambda i: i["date"])
        if object_id != "0":
            images = []
        page = images[start:start + count]
        print(f"UPnP Browse {object_id} [{start}..{start + len(page)}) of {len(images)}")
        didl = didl_for(page, self.host_ip)
        response = (
            '<?xml version="1.0" encoding="utf-8"?>'
            '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" '
            's:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body>'
            '<u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">'
            f"<Result>{escape(didl)}</Result><NumberReturned>{len(page)}</NumberReturned>"
            f"<TotalMatches>{len(images)}</TotalMatches><UpdateID>1</UpdateID>"
            "</u:BrowseResponse></s:Body></s:Envelope>")
        self.reply(200, response)


def soap_fault(code, text):
    return ('<?xml version="1.0" encoding="utf-8"?><s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">'
            '<s:Body><s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring><detail>'
            '<UPnPError xmlns="urn:schemas-upnp-org:control-1-0">'
            f"<errorCode>{code}</errorCode><errorDescription>{text}</errorDescription>"
            "</UPnPError></detail></s:Fault></s:Body></s:Envelope>")


def didl_for(images, host):
    base = f"http://{host}:{FILE_PORT}"
    items = []
    for image in images:
        i = image["id"]
        date = image["date"].strftime("%Y-%m-%dT%H:%M:%S")
        if image["video"]:
            upnp_class = "object.item.videoItem.movie"
            original = (f'<res protocolInfo="http-get:*:video/mp4:DLNA.ORG_PN=CAM_ORG" size="2000000">'
                        f"{base}/DO{i}.MP4</res>")
        else:
            upnp_class = "object.item.imageItem.photo"
            original = (f'<res protocolInfo="http-get:*:image/jpeg:DLNA.ORG_PN=CAM_ORG" size="{len(image["jpeg"])}">'
                        f"{base}/DO{i}.JPG</res>")
        raw = (f'<res protocolInfo="http-get:*:application/octet-stream:DLNA.ORG_PN=CAM_RAW" size="4000000">'
               f"{base}/DO{i}.RW2</res>") if image["raw"] else ""
        items.append(
            f'<item id="{i}" parentID="0" restricted="1"><dc:title>{image["title"]}</dc:title>'
            f"<upnp:class>{upnp_class}</upnp:class><dc:date>{date}</dc:date>{original}{raw}"
            f'<res protocolInfo="http-get:*:image/jpeg:DLNA.ORG_PN=CAM_TN">{base}/DT{i}.JPG</res>'
            f'<res protocolInfo="http-get:*:image/jpeg:DLNA.ORG_PN=CAM_LRGTN">{base}/DL{i}.JPG</res>'
            "</item>")
    return ('<DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
            'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" '
            'xmlns:pana="urn:schemas-panasonic-com:pana">' + "".join(items) + "</DIDL-Lite>")


def serve(server):
    threading.Thread(target=server.serve_forever, daemon=True).start()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bind", default="127.0.0.1", help="address to listen on (default 127.0.0.1)")
    ap.add_argument("--port", type=int, default=8082, help="cam.cgi port (default 8082; the real camera uses 80)")
    ap.add_argument("--fps", type=float, default=30, help="live view frame rate")
    ap.add_argument("--refuse", action="store_true", help="answer No to the pairing prompt")
    ap.add_argument("--quiet", action="store_true", help="don't print every command")
    ap.add_argument("--encrypted", action="store_true", help="newer pairing (req_acc_g/req_acc_e + X-SESSION_ID)")
    ap.add_argument("--model", default="DC-GH5", help="model the camera reports, e.g. DC-LX100 or DMC-GH4")
    args = ap.parse_args()
    global ENCRYPTED, MODEL
    ENCRYPTED = args.encrypted
    MODEL = args.model
    sys.stdout.reconfigure(line_buffering=True)

    cam = MockLumix(load_frames(), refuse=args.refuse)
    CamHandler.cam = cam
    CamHandler.verbose = not args.quiet
    MediaHandler.cam = cam
    biggest = max(len(f) for f in cam.frames)
    threading.Thread(target=stream_loop, args=(cam, args.fps), daemon=True).start()
    serve(ThreadingHTTPServer((args.bind, UPNP_PORT), MediaHandler))
    serve(ThreadingHTTPServer((args.bind, FILE_PORT), MediaHandler))
    server = ThreadingHTTPServer((args.bind, args.port), CamHandler)
    print(f"Mock LUMIX {NAME} on http://{args.bind}:{args.port}/cam.cgi, UPnP :{UPNP_PORT}, files :{FILE_PORT} "
          f"({len(cam.frames)} frames, largest {biggest // 1024} KB, {args.fps:g} fps, {len(cam.images)} files on card)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    sys.exit(main())
