#!/usr/bin/env python3
"""
Mock Sony camera (Camera Remote API, as on an a6000 / a7 III with Smart Remote Control)
for testing the app's Sony driver without a camera.

  * JSON-RPC on POST /sony/camera and /sony/avContent (the real camera: 192.168.122.1:8080).
    Like an a6000 it lists only a few APIs until startRecMode has been called.
  * Live view: startLiveview returns the URL of an endless HTTP stream of packets
    (8-byte common header + 128-byte payload header + JPEG + padding).
  * actTakePicture returns a postview URL; startBulbShooting / stopBulbShooting in BULB;
    setShootMode movie + startMovieRec / stopMovieRec; setTouchAFPosition.
  * Card: setCameraFunction "Contents Transfer", then avContent getSourceList / getContentList
    (paged), with thumbnail, large and original URLs.
  * The UPnP device description on port 64321 (/DmsRmtDesc.xml) gives the model name.

    python3 mock_sony.py                 # http://127.0.0.1:8086/sony/camera
    python3 mock_sony.py --bind 0.0.0.0  # reachable from a real iPhone on your Wi-Fi

In the app: Connect screen > Sony (or Auto) > Advanced > Camera address = 127.0.0.1:8086.
"""
import argparse
import datetime
import json
import os
import random
import struct
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mock_penf import load_frames  # noqa: E402  (same live-view frames as the PEN-F mock)

DESC_PORT = 64321
MODEL = "ILCE-6000"

F_NUMBERS = ["2.8", "3.2", "3.5", "4.0", "4.5", "5.0", "5.6", "6.3", "7.1", "8.0", "9.0", "10", "11", "13",
             "14", "16", "18", "20", "22"]
SHUTTERS = ["BULB", "30\"", "25\"", "20\"", "15\"", "13\"", "10\"", "8\"", "6\"", "5\"", "4\"", "3.2\"",
            "2.5\"", "2\"", "1.6\"", "1.3\"", "1\"", "0.8\"", "0.6\"", "0.5\"", "0.4\"", "1/3", "1/4", "1/5",
            "1/6", "1/8", "1/10", "1/13", "1/15", "1/20", "1/25", "1/30", "1/40", "1/50", "1/60", "1/80",
            "1/100", "1/125", "1/160", "1/200", "1/250", "1/320", "1/400", "1/500", "1/640", "1/800",
            "1/1000", "1/1250", "1/1600", "1/2000", "1/2500", "1/3200", "1/4000"]
ISOS = ["AUTO", "100", "125", "160", "200", "250", "320", "400", "500", "640", "800", "1000", "1250", "1600",
        "2000", "2500", "3200", "4000", "5000", "6400", "8000", "10000", "12800", "16000", "25600"]
WB = ["Auto WB", "Daylight", "Shade", "Cloudy", "Incandescent", "Fluorescent: Warm White (-1)",
      "Fluorescent: Cool White (0)", "Flash", "Color Temperature", "Custom 1"]
EXPOSURE_MODES = ["Intelligent Auto", "Program Auto", "Aperture", "Shutter", "Manual"]

BEFORE_REC_MODE = ["getVersions", "getMethodTypes", "getApplicationInfo", "getAvailableApiList", "getEvent",
                   "startRecMode", "stopRecMode"]
REC_MODE = BEFORE_REC_MODE + [
    "startLiveview", "stopLiveview", "actTakePicture", "awaitTakePicture", "setTouchAFPosition",
    "cancelTouchAFPosition", "getExposureMode", "getAvailableExposureMode", "getFNumber", "getAvailableFNumber",
    "setFNumber", "getShutterSpeed", "getAvailableShutterSpeed", "setShutterSpeed", "getIsoSpeedRate",
    "getAvailableIsoSpeedRate", "setIsoSpeedRate", "getExposureCompensation", "getAvailableExposureCompensation",
    "setExposureCompensation", "getWhiteBalance", "getAvailableWhiteBalance", "setWhiteBalance",
    "setShootMode", "getShootMode", "startMovieRec", "stopMovieRec", "setCameraFunction", "getCameraFunction",
    "startBulbShooting", "stopBulbShooting",
]

DESCRIPTION = """<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:av="urn:schemas-sony-com:av">
<device><deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>
<friendlyName>{model}</friendlyName><manufacturer>Sony Corporation</manufacturer><modelName>{model}</modelName>
<av:X_ScalarWebAPI_DeviceInfo><av:X_ScalarWebAPI_ServiceList>
<av:X_ScalarWebAPI_Service><av:X_ScalarWebAPI_ServiceType>camera</av:X_ScalarWebAPI_ServiceType>
<av:X_ScalarWebAPI_ActionList_URL>http://{host}:{port}/sony</av:X_ScalarWebAPI_ActionList_URL>
</av:X_ScalarWebAPI_Service></av:X_ScalarWebAPI_ServiceList></av:X_ScalarWebAPI_DeviceInfo>
</device></root>"""


class RPCError(Exception):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


class MockSony:
    def __init__(self, frames):
        self.lock = threading.Lock()
        self.frames = frames
        self.rec_mode = False
        self.function = "Remote Shooting"
        self.liveview = False
        self.exposure_mode = "Manual"
        self.f_number = "4.0"
        self.shutter = "1/125"
        self.iso = "AUTO"
        self.ev_index = 0
        self.wb = "Auto WB"
        self.shoot_mode = "still"
        self.recording = False
        self.bulb_since = None
        self.battery = 3
        self.counter = 1000
        self.images = []
        start = datetime.datetime.now() - datetime.timedelta(days=2)
        for k in range(130):   # more than one page of 100
            self.add_image(start + datetime.timedelta(minutes=k * 20), raw=(k % 4 == 0))

    def add_image(self, when=None, raw=False, video=False):
        self.counter += 1
        self.images.append({"id": self.counter, "name": f"DSC{self.counter % 10000:05d}",
                            "date": when or datetime.datetime.now(), "raw": raw, "video": video,
                            "jpeg": self.frames[(self.counter * 7) % len(self.frames)]})
        return self.images[-1]

    def apis(self):
        if not self.rec_mode:
            return list(BEFORE_REC_MODE)
        if self.function == "Contents Transfer":
            return BEFORE_REC_MODE + ["setCameraFunction", "getCameraFunction"]
        return list(REC_MODE)

    def event(self, host):
        result = [None] * 57
        result[0] = {"type": "availableApiList", "names": self.apis()}
        result[1] = {"type": "cameraStatus",
                     "cameraStatus": "MovieRecording" if self.recording else
                     ("StillCapturing" if self.bulb_since else "IDLE")}
        result[10] = [{"type": "storageInformation", "storageID": "Memory Card 1", "recordTarget": True,
                       "numberOfRecordableImages": 2400 - len(self.images), "recordableTime": -1}]
        result[12] = {"type": "cameraFunction", "currentCameraFunction": self.function,
                      "cameraFunctionCandidates": ["Remote Shooting", "Contents Transfer"]}
        result[18] = {"type": "exposureMode", "currentExposureMode": self.exposure_mode,
                      "exposureModeCandidates": [self.exposure_mode]}
        result[25] = {"type": "exposureCompensation", "currentExposureCompensation": self.ev_index,
                      "maxExposureCompensation": 9, "minExposureCompensation": -9, "stepIndexOfExposureCompensation": 1}
        result[27] = {"type": "fNumber", "currentFNumber": self.f_number, "fNumberCandidates": F_NUMBERS}
        result[29] = {"type": "isoSpeedRate", "currentIsoSpeedRate": self.iso, "isoSpeedRateCandidates": ISOS}
        result[32] = {"type": "shutterSpeed", "currentShutterSpeed": self.shutter, "shutterSpeedCandidates": SHUTTERS}
        result[33] = {"type": "whiteBalance", "currentWhiteBalanceMode": self.wb, "currentColorTemperature": -1}
        result[56] = {"type": "batteryInfo", "batteryInfo": [{"batteryID": "1", "status": "active",
                                                              "additionalStatus": "", "levelNumer": self.battery,
                                                              "levelDenom": 4, "description": ""}]}
        return result

    def require(self, method):
        if method not in self.apis():
            raise RPCError(12, "No Such Method" if method not in REC_MODE else "Forbidden")

    def camera(self, method, params, host):
        self.require(method)
        if method == "getVersions":
            return [["1.0", "1.1", "1.2", "1.3"]]
        if method == "getMethodTypes":
            return []
        if method == "getApplicationInfo":
            return ["Smart Remote Control", "2.1.4"]
        if method == "getAvailableApiList":
            return [self.apis()]
        if method == "getEvent":
            return self.event(host)
        if method == "startRecMode":
            self.rec_mode = True
            return [0]
        if method == "stopRecMode":
            self.rec_mode = False
            self.liveview = False
            return [0]
        if method == "startLiveview":
            self.liveview = True
            return [f"http://{host}/liveview/liveviewstream"]
        if method == "stopLiveview":
            self.liveview = False
            return [0]
        if method == "getExposureMode":
            return [self.exposure_mode]
        if method == "getAvailableExposureMode":
            return [self.exposure_mode, [self.exposure_mode]]   # set by the mode dial
        if method == "getAvailableFNumber":
            return [self.f_number, F_NUMBERS]
        if method == "setFNumber":
            return self.set_choice("f_number", params, F_NUMBERS)
        if method == "getAvailableShutterSpeed":
            return [self.shutter, SHUTTERS]
        if method == "setShutterSpeed":
            return self.set_choice("shutter", params, SHUTTERS)
        if method == "getAvailableIsoSpeedRate":
            return [self.iso, ISOS]
        if method == "setIsoSpeedRate":
            return self.set_choice("iso", params, ISOS)
        if method == "getAvailableExposureCompensation":
            return [self.ev_index, 9, -9, 1]
        if method == "setExposureCompensation":
            if not params or not isinstance(params[0], int) or not -9 <= params[0] <= 9:
                raise RPCError(3, "Illegal Argument")
            self.ev_index = params[0]
            return [0]
        if method == "getAvailableWhiteBalance":
            return [{"whiteBalanceMode": self.wb, "colorTemperature": -1},
                    [{"whiteBalanceMode": w, "colorTemperatureRange": [9900, 2500, 100] if w == "Color Temperature"
                      else []} for w in WB]]
        if method == "setWhiteBalance":
            return self.set_choice("wb", params[:1], WB)
        if method == "setTouchAFPosition":
            x, y = (params + [50, 50])[:2]
            print(f"  touch AF at {x:.0f}%, {y:.0f}%")
            return [0, {"AFResult": True, "AFType": "Touch"}]
        if method == "cancelTouchAFPosition":
            return [0]
        if method in ("actTakePicture", "awaitTakePicture"):
            if self.shutter == "BULB":
                raise RPCError(40400, "Use startBulbShooting in BULB")
            seconds = shutter_seconds(self.shutter)
            if seconds >= 1:
                time.sleep(min(seconds, 30))
            image = self.add_image()
            print(f"  shot {image['name']}.JPG")
            return [[f"http://{host}/postview/{image['id']}.jpg"]]
        if method == "startBulbShooting":
            if self.shutter != "BULB":
                raise RPCError(1, "Not in BULB")
            self.bulb_since = time.time()
            print("  bulb open")
            return [0]
        if method == "stopBulbShooting":
            if self.bulb_since:
                print(f"  bulb closed after {time.time() - self.bulb_since:.1f} s")
                self.add_image()
            self.bulb_since = None
            return [0]
        if method == "getShootMode":
            return [self.shoot_mode]
        if method == "setShootMode":
            self.shoot_mode = params[0] if params else "still"
            return [0]
        if method == "startMovieRec":
            if self.shoot_mode != "movie":
                raise RPCError(40401, "Camera Not Ready")
            self.recording = True
            print("  recording")
            return [0]
        if method == "stopMovieRec":
            if self.recording:
                self.add_image(video=True)
            self.recording = False
            print("  stopped recording")
            return [""]
        if method == "getCameraFunction":
            return [self.function]
        if method == "setCameraFunction":
            if not params or params[0] not in ("Remote Shooting", "Contents Transfer"):
                raise RPCError(3, "Illegal Argument")
            self.function = params[0]
            self.liveview = False
            print(f"  camera function: {self.function}")
            return [0]
        raise RPCError(12, "No Such Method")

    def set_choice(self, attr, params, choices):
        if not params or params[0] not in choices:
            raise RPCError(3, "Illegal Argument")
        setattr(self, attr, params[0])
        return [0]

    def av_content(self, method, params, host):
        if self.function != "Contents Transfer":
            raise RPCError(1, "Not in Contents Transfer")
        if method == "getSchemeList":
            return [[{"scheme": "storage"}]]
        if method == "getSourceList":
            return [[{"source": "storage:memoryCard1"}]]
        if method == "getContentList":
            req = params[0] if params else {}
            start, count = req.get("stIdx", 0), req.get("cnt", 50)
            ordered = sorted(self.images, key=lambda i: i["date"], reverse=True)
            items = []
            for image in ordered[start:start + count]:
                base = f"http://{host}/content/{image['id']}"
                originals = [{"fileName": f"{image['name']}.{'MP4' if image['video'] else 'JPG'}",
                              "stillObject": "jpeg", "url": f"{base}/original.jpg"}]
                if image["raw"]:
                    originals.append({"fileName": f"{image['name']}.ARW", "stillObject": "raw",
                                      "url": f"{base}/original.arw"})
                items.append({"uri": f"image:content?contentId={image['id']}", "title": image["name"],
                              "contentKind": "movie_mp4" if image["video"] else "still",
                              "createdTime": image["date"].astimezone().isoformat(timespec="seconds"),
                              "content": {"original": originals, "thumbnailUrl": f"{base}/thumb.jpg",
                                          "smallUrl": f"{base}/small.jpg", "largeUrl": f"{base}/large.jpg"}})
            return [items]
        raise RPCError(12, "No Such Method")


def shutter_seconds(value):
    if value.endswith('"'):
        return float(value[:-1])
    if value.startswith("1/"):
        return 1 / float(value[2:])
    return 0


def liveview_packet(sequence, jpeg):
    padding = (4 - len(jpeg) % 4) % 4
    common = struct.pack(">BBHI", 0xFF, 0x01, sequence & 0xFFFF, int(time.time() * 1000) & 0xFFFFFFFF)
    payload = (b"\x24\x35\x68\x79" + len(jpeg).to_bytes(3, "big") + bytes([padding])).ljust(128, b"\x00")
    return common + payload + jpeg + b"\x00" * padding


class Handler(BaseHTTPRequestHandler):
    cam = None
    fps = 30
    verbose = True
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    @property
    def host(self):
        return self.headers.get("Host") or "127.0.0.1:8086"

    def reply(self, status, body, ctype="application/json"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        path = urlsplit(self.path).path
        length = int(self.headers.get("Content-Length") or 0)
        try:
            request = json.loads(self.rfile.read(length) or b"{}")
        except ValueError:
            return self.reply(400, "{}")
        method, params, rid = request.get("method", ""), request.get("params", []), request.get("id", 1)
        if method != "getEvent" or self.verbose:
            print(f"{path} {method} {json.dumps(params)}")
        try:
            with self.cam.lock:
                if path == "/sony/camera":
                    result = self.cam.camera(method, params, self.host)
                elif path == "/sony/avContent":
                    result = self.cam.av_content(method, params, self.host)
                else:
                    return self.reply(404, "{}")
            self.reply(200, json.dumps({"result": result, "id": rid}))
        except RPCError as e:
            print(f"  -> error {e.code} {e.message}")
            self.reply(200, json.dumps({"error": [e.code, e.message], "id": rid}))

    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/liveview/liveviewstream":
            return self.stream()
        parts = path.strip("/").split("/")
        if parts[0] == "postview" and len(parts) == 2:
            return self.image_file(parts[1].split(".")[0], "large")
        if parts[0] == "content" and len(parts) == 3:
            return self.image_file(parts[1], parts[2].split(".")[0], parts[2].split(".")[-1])
        self.reply(404, "not found", "text/plain")

    def image_file(self, image_id, kind, ext="jpg"):
        with self.cam.lock:
            image = next((i for i in self.cam.images if str(i["id"]) == image_id), None)
        if image is None:
            return self.reply(404, "not found", "text/plain")
        if kind == "original" and ext == "arw":
            body, ctype = random.Random(image_id).randbytes(3_000_000), "application/octet-stream"
        else:
            body, ctype = image["jpeg"], "image/jpeg"
        print(f"file: {kind} {image['name']}.{ext} ({len(body)} bytes)")
        self.reply(200, body, ctype)

    def stream(self):
        with self.cam.lock:
            if not self.cam.liveview:
                return self.reply(404, "live view is off", "text/plain")
        print("live view stream: client connected")
        self.send_response(200)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Connection", "close")
        self.end_headers()
        sequence, index = 0, 0
        try:
            while True:
                with self.cam.lock:
                    if not self.cam.liveview:
                        break
                    frame = self.cam.frames[index % len(self.cam.frames)]
                self.wfile.write(liveview_packet(sequence, frame))
                self.wfile.flush()
                sequence += 1
                index += 1
                time.sleep(1 / self.fps)
        except (BrokenPipeError, ConnectionResetError):
            pass
        print("live view stream: closed")
        self.close_connection = True


class DescriptionHandler(BaseHTTPRequestHandler):
    api_port = 8086

    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if urlsplit(self.path).path != "/DmsRmtDesc.xml":
            self.send_response(404)
            self.end_headers()
            return
        host = (self.headers.get("Host") or "127.0.0.1").split(":")[0]
        body = DESCRIPTION.format(model=MODEL, host=host, port=self.api_port).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/xml")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bind", default="127.0.0.1", help="address to listen on (default 127.0.0.1)")
    ap.add_argument("--port", type=int, default=8086, help="API port (default 8086; the real camera uses 8080)")
    ap.add_argument("--fps", type=float, default=30, help="live view frame rate")
    ap.add_argument("--quiet", action="store_true", help="don't print every getEvent")
    args = ap.parse_args()
    sys.stdout.reconfigure(line_buffering=True)

    cam = MockSony(load_frames())
    Handler.cam = cam
    Handler.fps = args.fps
    Handler.verbose = not args.quiet
    DescriptionHandler.api_port = args.port
    threading.Thread(target=ThreadingHTTPServer((args.bind, DESC_PORT), DescriptionHandler).serve_forever,
                     daemon=True).start()
    server = ThreadingHTTPServer((args.bind, args.port), Handler)
    print(f"Mock Sony {MODEL} on http://{args.bind}:{args.port}/sony/camera, description :{DESC_PORT} "
          f"({len(cam.frames)} frames, {args.fps:g} fps, {len(cam.images)} files on card)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    sys.exit(main())
