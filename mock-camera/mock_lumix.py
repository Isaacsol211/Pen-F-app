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
import datetime
import math
import os
import random
import socket
import struct
import sys
import threading
import time
from http.server import ThreadingHTTPServer
from urllib.parse import parse_qsl, urlsplit
from xml.sax.saxutils import escape

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mock_penf import QuietHandler, arguments, load_frames, serve  # noqa: E402  (same frames as the PEN-F mock)

FPS = 30
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
WB = ["auto", "daylight", "cloudy", "shade", "flash", "incandescent", "halogen", "white_set1", "white_set2",
      "white_set3", "white_set4", "color_temp1"]
EXPOSURE = [("0" if t == 0 else (f"{t // 3}" if t % 3 == 0 else f"{t}/3")) for t in range(-15, 16)]
CHOICES = {"iso": ISO, "exposure": EXPOSURE, "whitebalance": WB}   # setsetting types = MockLumix attributes
STICKY_DRIVE = False   # --sticky-drive: answer ok to drive mode changes but keep the old one (seen on a GM1S)

# The extra settings, shaped like the real DMC-G7's allmenu (captured Nov 2026): headings with a
# title id, choices whose sub-items carry value2, cmd_value2="__value__" where the app fills in a
# number, and English names in a titlelist.
DRIVE = [  # (item id, title, cmd_value, [(value2, title)])
    ("1shoot", "Single", "normal", []),
    ("burst", "Burst Shooting", "burst", [("sh", "SH"), ("h", "H"), ("m", "M"), ("l", "L")]),
    ("4kphoto", "4K PHOTO", "4k_photo", [("burst", "4K Burst"), ("start_stop", "4K Burst(S/S)"),
                                         ("pre_burst", "4K Pre-Burst")]),
    ("autobracket", "Auto Bracket", "autobracket", [("3shot_1/3ev", "3 1/3"), ("5shot_2/3ev", "5 2/3"),
                                                    ("7shot_1ev", "7 1")]),
    ("selftimer", "Self Timer", "selftimer", [("10sec", "10sec."), ("10sec3shot", "10s / 3pictures"),
                                              ("2sec", "2sec.")]),
    ("stopmotion_interval", "Time Lapse/Animation", "stopmotion_interval",
     [("interval", "Time Lapse Shot"), ("stop_motion", "Animation")]),
]
HEADINGS = [  # (item id, title, cmd_type, [(value, title)], value2 placeholder)
    ("crtv_ctrl", "Creative Control", "creativectrl",
     [("pop", "Expressive"), ("retro", "Retro"), ("monochro", "Monochrome"), ("bleach_bypass", "Bleach Bypass"),
      ("diorama", "Miniature Effect")], False),
    ("ph_sty", "Photo Style", "colormode",
     [("standard", "Standard"), ("vivid", "Vivid"), ("natural", "Natural"), ("bw", "Monochrome"),
      ("scenery", "Scenery"), ("portrait", "Portrait"), ("cinelike_d", "Cinelike D"), ("cinelike_v", "Cinelike V")], True),
    ("filter_set", "Filter Select", "filter_setting",
     [("noeffect", "No Effect"), ("pop", "Expressive"), ("retro", "Retro"), ("monochro", "Monochrome"),
      ("bleach_bypass", "Bleach Bypass")], False),
    ("asprat", "Aspect Ratio", "aspectratio", [("4:3", "4:3"), ("3:2", "3:2"), ("16:9", "16:9"), ("1:1", "1:1")], False),
    ("quality", "Quality", "quality",
     [("fine", "Fine"), ("standard", "Standard"), ("raw_fine", "RAW+Fine"), ("raw_standard", "RAW+Standard"),
      ("raw", "RAW")], False),
    ("lightmet", "Metering Mode", "lightmetering",
     [("multi", "Multi Metering"), ("center", "Center Weighted"), ("spot", "Spot")], False),
    ("flash", "Flash Mode", "flash",
     [("forcedflashon", "Forced Flash On"), ("slowsync", "Slow Sync."), ("forcedflashoff", "Forced Flash Off")], False),
    ("videoformat", "Rec Format", "videoformat", [("avchd", "AVCHD"), ("mp4", "MP4")], False),
    ("v_quality", "Video Rec Quality", "videoquality",
     [("mp4_30p_100mbps_4k", "MP4(3840x2160)30p 100Mbps"), ("mp4_60p_28mbps", "MP4(1920x1080)60p 28Mbps"),
      ("mp4_30p_20mbps", "MP4(1920x1080)30p 20Mbps")], False),
]
AF_MODES = [("facedetection", "Face/Eye Detection"), ("aftracking", "Tracking"), ("49area", "49-Area"),
            ("1area", "1-Area"), ("pinpoint", "Pinpoint")]
CUSTOM_MULTI = [("vertical", "Vertical Pattern"), ("horizontal", "Horizontal Pattern")]
PEAKING = [("off", "Off"), ("low", "Low"), ("high", "High")]
KELVIN = (2500, 10000, 100)


def extra_defaults():
    return {"drivemode": ("normal", ""), "creativectrl": ("pop", ""), "colormode": ("standard", ""),
            "filter_setting": ("noeffect", ""), "aspectratio": ("4:3", ""), "quality": ("fine", ""),
            "lightmetering": ("multi", ""), "flash": ("forcedflashoff", ""), "videoformat": ("mp4", ""),
            "videoquality": ("mp4_30p_100mbps_4k", ""), "afmode": ("1area", ""), "peaking": ("off", ""),
            "pictsize": ("16m", "")}


G7_MENU = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "dmc-g7-allmenu.xml")


def allmenu_body():
    """The <menuset> served for getinfo&type=allmenu: the real G7's menu for --model DMC-G7,
    otherwise one built in the same shape."""
    if "G7" in MODEL.upper() and os.path.exists(G7_MENU):
        with open(G7_MENU, encoding="utf-8") as f:
            return "".join(line for line in f if not line.startswith("<!--"))
    items = "".join(f'<item id="menu_item_id_iso_{v}" func_type="select" cmd_mode="setsetting" '
                    f'cmd_type="iso" cmd_value="{v}"/>' for v in ISO)
    extras, titles = menu_items()
    return (f'<menuset model="{MODEL}"><mainmenu><photosettings>{items}</photosettings></mainmenu>'
            + extras + titles + "</menuset>")


def menu_rules():
    """From the served menu: cmd_type -> allowed (value, value2), and the colour temperature range."""
    import xml.etree.ElementTree as ET
    allowed, kelvin = {}, KELVIN
    for item in ET.fromstring(allmenu_body()).iter("item"):
        kind, value = item.get("cmd_type"), item.get("cmd_value")
        if not kind or not value or value == "__value__":
            continue
        if kind == "whitebalance" and value == "color_temp" and item.get("min_val"):
            kelvin = (int(item.get("min_val")), int(item.get("max_val")), int(item.get("step_val") or 100))
            continue
        value2 = item.get("cmd_value2") or ""
        allowed.setdefault(kind, set()).add((value, "" if value2 == "__value__" else value2))
    return allowed, kelvin


def menu_items():
    """The allmenu body for the extra settings, and the titles it refers to."""
    titles = {}

    def item(item_id, title, attrs="", inner=""):
        titles[f"title_{item_id}"] = title
        body = f"<group>{inner}</group>" if inner else ""
        return f'<item id="menu_item_id_{item_id}" title_id="title_{item_id}" {attrs}>{body}</item>'

    def setting(kind, value, value2=None):
        extra = f' cmd_value2="{escape(value2)}"' if value2 is not None else ""
        return f'cmd_mode="setsetting" cmd_type="{kind}" cmd_value="{escape(value)}"{extra}'

    photo = []
    for item_id, title, kind, options, placeholder in HEADINGS:
        inner = "".join(item(f"{item_id}_{v}".replace(":", "_"), t, setting(kind, v, "__value__" if placeholder else None))
                        for v, t in options)
        photo.append(item(item_id, title, f'func_type="select"', inner))
    lo, hi, step = KELVIN
    wb = "".join(item(f"whitebalance_{v}", v.title(), setting("whitebalance", v)) for v in WB if v != "color_temp1")
    wb += item("whitebalance_color_temp", "Color Temperature",
               f'min_val="{lo}" max_val="{hi}" step_val="{step}" ' + setting("whitebalance", "color_temp", "__value__"))
    quick = [item("whitebalance", "White Balance", 'func_type="sp_embeded_whitebalance"', wb)]
    afs = "".join(item(f"afmode_{v}", t, setting("afmode", v)) for v, t in AF_MODES[:3])
    afs += item("afmode_custom_multi", "Custom Multi", 'func_type="select" ' + setting("afmode", "custom_multi"),
                "".join(item(f"afmode_custom_multi_{v2}", t, setting("afmode", "custom_multi", v2)) for v2, t in CUSTOM_MULTI))
    afs += "".join(item(f"afmode_{v}", t, setting("afmode", v)) for v, t in AF_MODES[3:])
    quick.append(item("afmode", "AF Mode", 'func_type="sp_embeded_afmode"', afs))
    for item_id, title, value, subs in DRIVE:
        if subs:
            inner = "".join(item(f"{item_id}_{v2}".replace("/", "_"), t, setting("drivemode", value, v2)) for v2, t in subs)
            quick.append(item(item_id, title, 'func_type="select" ' + setting("drivemode", value), inner))
        else:
            quick.append(item(item_id, title, setting("drivemode", value)))
    quick.append(item("peaking", "Peaking", 'func_type="sp_embeded_peaking"',
                      "".join(item(f"peaking_{v}", t, setting("peaking", v)) for v, t in PEAKING)))
    xml = ("<photosettings><menu>" + "".join(photo) + "</menu></photosettings>"
           "<qmenu2><menu>" + "".join(quick) + "</menu></qmenu2>")
    title_xml = "".join(f'<title id="{k}">{escape(v)}</title>' for k, v in titles.items())
    return xml, f'<titlelist model="{MODEL}"><language code="en" default="yes">{title_xml}</language></titlelist>'


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
        self.kelvin = "5500"
        self.extras = extra_defaults()
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


def stream_loop(cam):
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
        time.sleep(max(0.0, 1.0 / FPS - (time.time() - started)))


# ---------------------------------------------------------------------------- cam.cgi

class CamHandler(QuietHandler):
    cam: MockLumix = None

    def result(self, code="ok", extra=""):
        if code != "ok":
            print(f"  -> {code}")
        self.reply(200, f'<?xml version="1.0" encoding="UTF-8"?>\n<camrply><result>{code}</result>{extra}</camrply>')

    def csv(self, text):
        self.reply(200, text, "text/plain")

    def do_GET(self):
        url = urlsplit(self.path)
        q = dict(parse_qsl(url.query, keep_blank_values=True))
        if url.path != "/cam.cgi":
            return self.reply(404, "not found", "text/plain")
        mode = q.get("mode", "")
        if mode != "getstate":
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
    def approved(self, key, name):
        """The camera's Yes/No prompt: answers "under research" twice, then Yes (No with --refuse)."""
        cam = self.cam
        if key in cam.paired:
            return True
        cam.pairing_attempts[key] = cam.pairing_attempts.get(key, 0) + 1
        if cam.pairing_attempts[key] <= 2:
            print(f"  (camera shows: Connect to {name}? Yes / No)")
            self.csv("ok_under_research")
        elif cam.refuse:
            cam.pairing_attempts[key] = 0
            self.result("err_user_refused")
        else:
            cam.paired.add(key)
            return True
        return False

    def mode_accctrl(self, q):
        if ENCRYPTED:
            return self.encrypted_accctrl(q)
        if q.get("type") != "req_acc":
            return self.result("err_param")
        uuid = q.get("value", "")
        if not uuid.startswith("4D454930-0100-1000-8001-"):
            return self.result("err_unsuitable_app")
        if self.approved(uuid, q.get("value2", "?")):
            self.csv(f"ok,{NAME},remote,encrypted")

    def encrypted_accctrl(self, q):
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
        if self.approved(udn, name):
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
            return self.result("ok", allmenu_body())
        if kind == "curmenu":
            # Like a real body: Creative Control is greyed out unless the dial is on C, and 4K Photo
            # can't record RAW.
            cam = self.cam
            four_k = cam.extras["drivemode"][0] == "4k_photo"
            rows = ['<item id="menu_item_id_recmode" enable="yes" value="manual_exposure" />',
                    '<item id="menu_item_id_crtv_ctrl" enable="no" />',
                    f'<item id="menu_item_id_filter_set" enable="yes" value="{cam.extras["filter_setting"][0]}" />']
            for v in ("raw_fine", "raw_standard", "raw"):
                rows.append(f'<item id="menu_item_id_quality_{v}" enable="{"no" if four_k else "yes"}" />')
            return self.result("ok", f'<menuinfo model="{MODEL}">' + "".join(rows) + "</menuinfo>")
        self.result("err_param")

    def mode_getstate(self, q):
        cam = self.cam
        cam.last_poll = time.time()
        self.result("ok", f"<state><batt>{cam.battery}/3</batt><cammode>{cam.mode}</cammode>"
                          f"<remaincapacity>{2400 - len(cam.images)}</remaincapacity><temperature>normal</temperature></state>")

    # -- settings ----------------------------------------------------------------
    def mode_getsetting(self, q):
        cam = self.cam
        kind = q.get("type")
        values = {
            "focal": code_text(cam.focal), "shtrspeed": code_text(cam.shutter), "iso": cam.iso,
            "exposure": cam.exposure, "whitebalance": cam.whitebalance, "liveviewsize": cam.stream_size,
        }
        if kind in cam.extras:
            value, value2 = cam.extras[kind]
            return self.result("ok", f'<settingvalue {kind}="{escape(value)}">{escape(value2)}</settingvalue>')
        if kind not in values:
            return self.result("err_param")
        text = cam.kelvin if cam.whitebalance == "color_temp" and kind == "whitebalance" else ""
        self.result("ok", f'<settingvalue {kind}="{values[kind]}">{text}</settingvalue>')

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
        elif kind == "whitebalance" and value == "color_temp":
            lo, hi, step = menu_rules()[1]
            k = q.get("value2", "")
            if not k.isdigit() or not (lo <= int(k) <= hi) or (int(k) - lo) % step:
                return self.result("err_param")
            cam.whitebalance, cam.kelvin = "color_temp", k
            print(f"  white balance now {k} K")
        elif kind in CHOICES:
            if value not in CHOICES[kind]:
                return self.result("err_param")
            setattr(cam, kind, value)
        elif kind in cam.extras:
            pair = (value, q.get("value2", ""))
            allowed = menu_rules()[0].get(kind, set())
            # A choice can be sent without its second part (the camera keeps the last one).
            if pair not in allowed and not (not pair[1] and any(v == value for v, _ in allowed)):
                return self.result("err_param")
            if kind == "creativectrl":
                return self.result("err_reject")   # the dial isn't on C
            if kind == "drivemode" and STICKY_DRIVE:
                print("  (says ok, keeps the old drive mode)")
                return self.result()
            cam.extras[kind] = pair
            print(f"  {kind} now {value}" + (f" / {pair[1]}" if pair[1] else ""))
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


class MediaHandler(QuietHandler):
    """Port 60606 (UPnP) and 50001 (files) share this handler; the port decides which paths exist."""
    cam: MockLumix = None
    content_type = "text/xml; charset=utf-8"

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
                return self.reply(200, DEVICE_DESCRIPTION.format(udn=UDN, capability=capability, model=MODEL))
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


def main():
    ap = arguments(__doc__, 8082, 80)
    ap.add_argument("--refuse", action="store_true", help="answer No to the pairing prompt")
    ap.add_argument("--encrypted", action="store_true", help="newer pairing (req_acc_g/req_acc_e + X-SESSION_ID)")
    ap.add_argument("--model", default="DC-GH5",
                    help="model the camera reports, e.g. DC-LX100 or DMC-GH4; DMC-G7 serves the real G7's menu")
    ap.add_argument("--sticky-drive", action="store_true",
                    help="answer ok to drive mode changes but keep the old one (a GM1S does this)")
    args = ap.parse_args()
    global ENCRYPTED, MODEL, STICKY_DRIVE
    ENCRYPTED = args.encrypted
    MODEL = args.model
    STICKY_DRIVE = args.sticky_drive

    cam = MockLumix(load_frames(), refuse=args.refuse)
    CamHandler.cam = MediaHandler.cam = cam
    biggest = max(len(f) for f in cam.frames)
    threading.Thread(target=stream_loop, args=(cam,), daemon=True).start()
    serve(ThreadingHTTPServer((args.bind, UPNP_PORT), MediaHandler), background=True)
    serve(ThreadingHTTPServer((args.bind, FILE_PORT), MediaHandler), background=True)
    server = ThreadingHTTPServer((args.bind, args.port), CamHandler)
    print(f"Mock LUMIX {NAME} on http://{args.bind}:{args.port}/cam.cgi, UPnP :{UPNP_PORT}, files :{FILE_PORT} "
          f"({len(cam.frames)} frames, largest {biggest // 1024} KB, {FPS} fps, {len(cam.images)} files on card)")
    serve(server)


if __name__ == "__main__":
    sys.exit(main())
