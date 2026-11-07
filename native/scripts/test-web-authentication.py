#!/usr/bin/env python3
# SPDX-License-Identifier: MPL-2.0
"""Run the app's session handler and Chromium against an isolated local identity provider."""
import http.server
import os
import pathlib
import plistlib
import socket
import subprocess
import tempfile
import threading

native = pathlib.Path(__file__).resolve().parents[1]
build = pathlib.Path(os.environ.get("BROWSER_BUILD_ROOT", native / "build"))
seen = {}


class Provider(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split("?")[0]
        seen.setdefault(path, []).append(self.headers.get("Cookie", ""))
        self.send_response(302 if path.startswith("/finish/") else 200)
        content = ""
        if path == "/seed":
            self.send_header("Set-Cookie", "account=regular; Path=/; HttpOnly")
            content = "<title>Seeded</title>"
        elif path in ("/regular", "/private-a", "/private-b", "/private-legacy"):
            case = path[1:]
            self.send_header("Set-Cookie", f"flow={case}; Path=/; HttpOnly")
            content = (f'<iframe src="/frame"></iframe><script>onload=()=>'
                       f'setTimeout(()=>location.href="/finish/{case}",240)</script>')
        elif path == "/frame":
            content = '<script>location.href="arctest://subframe-must-not-complete"</script>'
        elif path == "/popup":
            content = ('<!doctype html><a style="position:fixed;inset:0" target="_blank" href="/finish/popup">Continue</a>'
                       '<script>onclick=()=>fetch("/clicked")</script>')
        elif path.startswith("/finish/"):
            case = path[len("/finish/"):]
            target = (f"https://auth-callback.invalid/finished?case={case}#result" if case == "private-a"
                      else f"arctest://done?case={case}&state=A%2FB#result")
            self.send_header("Location", target)
        self.send_header("Content-Type", "text/html")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(content.encode())

    def log_message(self, *args):
        pass


def run():
    with tempfile.TemporaryDirectory(prefix="web-auth-check.", dir=build) as temp, \
            http.server.ThreadingHTTPServer(("127.0.0.1", 0), Provider) as server:
        root = pathlib.Path(temp)
        app = root / "Arc Reborn.app"
        subprocess.run(["cp", "-cR", build / app.name, app], check=True)
        plist = app / "Contents/Info.plist"
        with plist.open("rb") as stream:
            info = plistlib.load(stream)
        caps = info["ASWebAuthenticationSessionWebBrowserSupportCapabilities"]
        assert all(caps.get(key) is True for key in ("IsSupported", "EphemeralBrowserSessionIsSupported",
                                                    "CallbackURLMatchingIsSupported"))
        info["CFBundleIdentifier"] = "local.browser.web-authentication-test"
        with plist.open("wb") as stream:
            plistlib.dump(info, stream)
        executable = app / "Contents/MacOS/Arc Reborn"
        sources = sorted(p for p in (native / "Sources").glob("*.swift") if p.name != "main.swift")
        subprocess.run(["xcrun", "swiftc", "-j", "6", "-Onone", "-swift-version", "5", "-target", "arm64-apple-macosx13.0",
                        "-import-objc-header", native / "Bridge/BrowserBridge.h", *sources,
                        native / "Tests/WebAuthenticationHarness.swift", build / "cmake/libBrowserBridge.a",
                        build / "cmake/libcef_dll_wrapper/libcef_dll_wrapper.a", "-lc++", "-framework", "Cocoa",
                        "-framework", "IOSurface", "-framework", "Security", "-framework", "SecurityInterface",
                        "-F", native / "vendor/sparkle-2.10.1", "-framework", "Sparkle", "-Xlinker", "-rpath",
                        "-Xlinker", "@executable_path/../Frameworks", "-Xlinker", "-ObjC", "-o", executable], check=True)
        subprocess.run(["codesign", "--force", "--sign", "-", app], check=True)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        with socket.socket() as port:
            port.bind(("127.0.0.1", 0))
            debug_port = str(port.getsockname()[1])
        profile = root / "profile"
        try:
            result = subprocess.run([executable], timeout=100, env={**os.environ, "BROWSER_NATIVE_TEST_DATA":str(profile),
                                    "BROWSER_NATIVE_DEBUG_PORT":debug_port, "BROWSER_WEBAUTH_ORIGIN":f"http://127.0.0.1:{server.server_port}"})
            if result.returncode:
                print("Test provider paths:", list(seen))
                for log in (profile / "Chromium/Diagnostics").glob("*/process.log"):
                    print(log.read_text(errors="replace")[-5000:])
                result.check_returncode()
        finally:
            server.shutdown()
        assert "/never" not in seen
        assert seen["/regular"] == ["account=regular"]
        first = "private-a" if "/private-a" in seen else "private-legacy"
        assert seen["/" + first] == seen["/private-b"] == [""]
        for case in (first, "private-b"):
            assert seen["/finish/" + case] == ["flow=" + case]
        assert not list(profile.rglob("Profile-auth-*"))
        print("PASS Chromium cookies shared with the active profile and isolated per private request")


if __name__ == "__main__":
    run()
