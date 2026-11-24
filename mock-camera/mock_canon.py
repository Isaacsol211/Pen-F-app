#!/usr/bin/env python3
"""
Mock Canon EOS R6 speaking CCAPI (Canon Camera Control API), for testing the app's Canon driver
without a camera (or a CCAPI activation).

  * GET /ccapi lists the APIs per version, like a real body after activation.
  * Device information, battery, shooting settings (tv, av, iso, exposure, wb with "ability"
    lists; shootingmodedial read-only), PUT to change them (400 for values not in the list).
  * Live view: POST shooting/liveview {"liveviewsize": "small"}, then GET liveview/flip = one JPEG.
  * Shutter: POST shooting/control/shutterbutton {"af": true}; shutterbutton/manual half_press /
    full_press / release (Bulb when tv is "bulb"); moviemode + recbutton.
  * event/polling?continue=off reports battery and "addedcontents" since the last poll.
  * Card: contents → sd → 100CANON → ?kind=number / ?page=N, files with ?kind=thumbnail|display,
    plain GET for the original.

    python3 mock_canon.py                 # http://127.0.0.1:8084/ccapi
    python3 mock_canon.py --bind 0.0.0.0  # reachable from a real iPhone on your Wi-Fi

In the app: Connect screen > Canon (or Auto) > Advanced > Camera address = 127.0.0.1:8084.
"""
import datetime
import json
import os
import random
import sys
import threading
import time
from http.server import ThreadingHTTPServer
from urllib.parse import parse_qsl, urlsplit

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mock_penf import QuietHandler, arguments, load_frames, serve  # noqa: E402  (same frames as the PEN-F mock)

V = "/ccapi/ver100/"
PER_PAGE = 100

TV = ["bulb", "30\"", "25\"", "20\"", "15\"", "13\"", "10\"", "8\"", "6\"", "5\"", "4\"", "3\"2", "2\"5", "2\"",
      "1\"6", "1\"3", "1\"", "0\"8", "0\"6", "0\"5", "0\"4", "0\"3", "1/4", "1/5", "1/6", "1/8", "1/10", "1/13",
      "1/15", "1/20", "1/25", "1/30", "1/40", "1/50", "1/60", "1/80", "1/100", "1/125", "1/160", "1/200",
      "1/250", "1/320", "1/400", "1/500", "1/640", "1/800", "1/1000", "1/1250", "1/1600", "1/2000", "1/2500",
      "1/3200", "1/4000", "1/5000", "1/6400", "1/8000"]
AV = ["f1.8", "f2.0", "f2.2", "f2.5", "f2.8", "f3.2", "f3.5", "f4.0", "f4.5", "f5.0", "f5.6", "f6.3", "f7.1",
      "f8.0", "f9.0", "f10", "f11", "f13", "f14", "f16", "f18", "f20", "f22"]
ISO = ["auto", "100", "125", "160", "200", "250", "320", "400", "500", "640", "800", "1000", "1250", "1600",
       "2000", "2500", "3200", "4000", "5000", "6400", "8000", "10000", "12800", "16000", "20000", "25600"]
EXPOSURE = ["-3", "-2_2/3", "-2_1/3", "-2", "-1_2/3", "-1_1/3", "-1", "-0_2/3", "-0_1/3", "+0", "+0_1/3",
            "+0_2/3", "+1", "+1_1/3", "+1_2/3", "+2", "+2_1/3", "+2_2/3", "+3"]
WB = ["auto", "awbwhite", "daylight", "shade", "cloudy", "tungsten", "whitefluorescent", "flash", "custom",
      "colortemp"]

APIS = {
    "ver100": [
        ("deviceinformation", "g"), ("devicestatus/battery", "g"),
        ("shooting/settings", "g"), ("shooting/settings/shootingmodedial", "g"),
        ("shooting/settings/tv", "gp"), ("shooting/settings/av", "gp"), ("shooting/settings/iso", "gp"),
        ("shooting/settings/exposure", "gp"), ("shooting/settings/wb", "gp"),
        ("shooting/liveview", "o"), ("shooting/liveview/flip", "g"), ("shooting/liveview/afframeposition", "p"),
        ("shooting/control/shutterbutton", "o"), ("shooting/control/shutterbutton/manual", "o"),
        ("shooting/control/moviemode", "o"), ("shooting/control/recbutton", "o"),
        ("shooting/control/drivefocus", "o"),
        ("event/polling", "g"), ("contents", "g"),
    ],
    "ver110": [("devicestatus/batterylist", "g"), ("shooting/control/recbutton", "o")],
}


class Busy(Exception):
    pass


class BadValue(Exception):
    pass


class MockCanon:
    def __init__(self, frames):
        self.lock = threading.Lock()
        self.frames = frames
        self.frame_index = 0
        self.settings = {"shootingmodedial": "m", "tv": "1/125", "av": "f4.0", "iso": "auto",
                         "exposure": "+0", "wb": "auto"}
        self.liveview = None
        self.movie_mode = False
        self.recording = False
        self.bulb_since = None
        self.busy_until = 0
        self.added = []
        self.battery = "high"
        self.counter = 2000
        self.files = []   # dicts: name, date, jpeg, kind
        start = datetime.datetime.now() - datetime.timedelta(days=3)
        for k in range(140):
            self.add_file(start + datetime.timedelta(minutes=17 * k), raw=(k % 5 == 0))

    def add_file(self, when=None, raw=False, movie=False):
        self.counter += 1
        base = f"IMG_{self.counter % 10000:04d}" if not movie else f"MVI_{self.counter % 10000:04d}"
        jpeg = self.frames[(self.counter * 7) % len(self.frames)]
        names = [base + (".MP4" if movie else ".JPG")] + ([base + ".CR3"] if raw else [])
        for name in names:
            self.files.append({"name": name, "date": when or datetime.datetime.now(), "jpeg": jpeg})
        return [V + "contents/sd/100CANON/" + n for n in names]

    def shoot(self):
        if time.time() < self.busy_until:
            raise Busy()
        seconds = tv_seconds(self.settings["tv"])
        if seconds >= 1:
            time.sleep(min(seconds, 30))
        paths = self.add_file()
        self.added += paths
        self.busy_until = time.time() + 0.4
        print(f"  shot {paths[0].rsplit('/', 1)[-1]}")


def tv_seconds(value):
    if value.startswith("1/"):
        return 1 / float(value[2:])
    if '"' in value:
        whole, _, frac = value.partition('"')
        return float(f"{whole}.{frac or 0}")
    return 0


class Handler(QuietHandler):
    cam = None
    content_type = "application/json"

    def reply(self, status, body=None, ctype=None):
        super().reply(status, body if isinstance(body, (bytes, str)) else json.dumps(body or {}), ctype)

    def handle_any(self):
        method = self.command
        url = urlsplit(self.path)
        q = dict(parse_qsl(url.query))
        path = url.path.rstrip("/")
        length = int(self.headers.get("Content-Length") or 0)
        try:
            payload = json.loads(self.rfile.read(length)) if length else {}
        except ValueError:
            payload = {}
        quiet = path.endswith("liveview/flip") or path.endswith("event/polling") or "kind" in q
        if not quiet:
            print(f"{method} {self.path} {json.dumps(payload) if payload else ''}")
        if path == "/ccapi":
            return self.reply(200, {ver: [{"path": f"/ccapi/{ver}/{p}", "get": "g" in m, "put": "p" in m,
                                           "post": "o" in m, "delete": "d" in m} for p, m in items]
                                    for ver, items in APIS.items()})
        if path.startswith("/ccapi/ver110/"):
            path = V + path[len("/ccapi/ver110/"):]
        if not path.startswith(V):
            return self.reply(404, {"message": "Not found"})
        feature = path[len(V):]
        cam = self.cam
        try:
            with cam.lock:
                return self.route(method, feature, q, payload)
        except Busy:
            return self.reply(503, {"message": "Device busy"})
        except BadValue:
            return self.reply(400, {"message": "Invalid parameter"})

    def route(self, method, feature, q, payload):
        cam = self.cam
        if feature == "deviceinformation":
            return self.reply(200, {"manufacturer": "Canon Inc.", "productname": "Canon EOS R6"})
        if feature == "devicestatus/battery":
            return self.reply(200, {"name": "LP-E6NH", "kind": "battery", "level": cam.battery, "quality": "good"})
        if feature == "devicestatus/batterylist":
            return self.reply(200, {"batterylist": [{"position": "camera", "name": "LP-E6NH", "kind": "battery",
                                                     "level": cam.battery, "quality": "good"}]})
        if feature == "shooting/settings":
            return self.reply(200, {k: self.setting_json(k) for k in cam.settings})
        if feature.startswith("shooting/settings/"):
            key = feature.rsplit("/", 1)[-1]
            if key not in cam.settings:
                return self.reply(404, {"message": "Not found"})
            if method == "GET":
                return self.reply(200, self.setting_json(key))
            if key == "shootingmodedial":
                return self.reply(400, {"message": "Read only"})
            value = payload.get("value")
            if value not in ABILITY[key]:
                raise BadValue()
            cam.settings[key] = value
            print(f"  {key} = {value}")
            return self.reply(200, self.setting_json(key))
        if feature == "shooting/liveview":
            size = payload.get("liveviewsize", "off")
            cam.liveview = None if size == "off" else size
            print(f"  live view {size}")
            return self.reply(200)
        if feature == "shooting/liveview/flip":
            if not cam.liveview:
                return self.reply(503, {"message": "Live view not started"})
            frame = cam.frames[cam.frame_index % len(cam.frames)]
            cam.frame_index += 1
            return self.reply(200, frame, "image/jpeg")
        if feature == "shooting/liveview/afframeposition":
            print(f"  AF frame at {payload.get('positionx')}, {payload.get('positiony')}")
            return self.reply(200)
        if feature == "shooting/control/shutterbutton":
            cam.shoot()
            return self.reply(200)
        if feature == "shooting/control/shutterbutton/manual":
            action = payload.get("action")
            if action == "half_press":
                return self.reply(200)
            if action == "full_press":
                if cam.settings["tv"] == "bulb":
                    cam.bulb_since = time.time()
                    print("  bulb open")
                else:
                    cam.shoot()
                return self.reply(200)
            if action == "release":
                if cam.bulb_since:
                    print(f"  bulb closed after {time.time() - cam.bulb_since:.1f} s")
                    cam.added += cam.add_file()
                    cam.bulb_since = None
                return self.reply(200)
            raise BadValue()
        if feature == "shooting/control/drivefocus":
            steps = {"near3": -300, "near2": -100, "near1": -20, "far1": 20, "far2": 100, "far3": 300}
            value = payload.get("value")
            if value not in steps:
                raise BadValue()
            if not cam.liveview:
                return self.reply(503, {"message": "Live view not started"})
            cam.focus_pos = max(0, min(10000, getattr(cam, "focus_pos", 2000) + steps[value]))
            print(f"  drive focus {value} -> {cam.focus_pos}/10000")
            return self.reply(200)
        if feature == "shooting/control/moviemode":
            cam.movie_mode = payload.get("action") == "on"
            return self.reply(200)
        if feature == "shooting/control/recbutton":
            action = payload.get("action")
            if action == "start":
                if not cam.movie_mode:
                    return self.reply(503, {"message": "Mode not supported"})
                cam.recording = True
                print("  recording")
            elif action == "stop":
                if cam.recording:
                    cam.added += cam.add_file(movie=True)
                cam.recording = False
                print("  stopped recording")
            return self.reply(200)
        if feature == "event/polling":
            changes = {"battery": {"name": "LP-E6NH", "kind": "battery", "level": cam.battery, "quality": "good"}}
            if cam.added:
                changes["addedcontents"] = cam.added
                cam.added = []
            return self.reply(200, changes)
        if feature == "contents":
            return self.reply(200, {"path": [V + "contents/sd"]})
        if feature == "contents/sd":
            return self.reply(200, {"path": [V + "contents/sd/100CANON"]})
        if feature == "contents/sd/100CANON":
            ordered = sorted(cam.files, key=lambda f: f["name"])
            if q.get("kind") == "number":
                return self.reply(200, {"contentsnumber": len(ordered),
                                        "pagenumber": max(1, (len(ordered) + PER_PAGE - 1) // PER_PAGE)})
            page = int(q.get("page", "1"))
            chunk = ordered[(page - 1) * PER_PAGE:page * PER_PAGE]
            return self.reply(200, {"path": [V + "contents/sd/100CANON/" + f["name"] for f in chunk]})
        if feature.startswith("contents/sd/100CANON/"):
            name = feature.rsplit("/", 1)[-1]
            f = next((f for f in cam.files if f["name"] == name), None)
            if f is None:
                return self.reply(404, {"message": "Not found"})
            if q.get("kind") in ("thumbnail", "display"):
                return self.reply(200, f["jpeg"], "image/jpeg")
            print(f"file: {name} (original)")
            if name.endswith((".CR3", ".MP4")):
                return self.reply(200, random.Random(name).randbytes(3_000_000), "application/octet-stream")
            return self.reply(200, f["jpeg"], "image/jpeg")
        return self.reply(404, {"message": "Not found"})

    def setting_json(self, key):
        value = self.cam.settings[key]
        return {"value": value} if key == "shootingmodedial" else {"value": value, "ability": ABILITY[key]}

    do_GET = do_PUT = do_POST = handle_any


ABILITY = {"tv": TV, "av": AV, "iso": ISO, "exposure": EXPOSURE, "wb": WB}


def main():
    args = arguments(__doc__, 8084, 8080).parse_args()
    cam = MockCanon(load_frames())
    Handler.cam = cam
    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"Mock Canon EOS R6 (CCAPI) on http://{args.bind}:{args.port}/ccapi "
          f"({len(cam.frames)} frames, {len(cam.files)} files on card)")
    serve(server)


if __name__ == "__main__":
    sys.exit(main())
