#!/usr/bin/env python3
"""Exercise native tab sleep/wake in isolated CEF profiles, using an accelerated clock."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os
import plistlib
import subprocess
import sys
import socket
import tempfile
import threading
import time
import io
import wave

native = Path(__file__).resolve().parents[1]
build = Path(os.environ.get("BROWSER_BUILD_ROOT", native / "build/development")).resolve()

# Each exercise exposes a live invariant for confirmation after switching back.
pages = {
    "draft": """let field=document.body.appendChild(document.createElement('textarea'));
        field.value='Brouillon écrit'; verify=()=>field.value==='Brouillon écrit';""",
    "editor": """let editor=document.body.appendChild(document.createElement('div'));
        editor.contentEditable='true';editor.textContent='Note';
        editor.dispatchEvent(new InputEvent('input',{bubbles:true,composed:true}));
        const saved=editor.textContent; editor.remove(); verify=()=>saved==='Note';""",
    "frame": """let f=document.body.appendChild(document.createElement('iframe'));f.src='/field';
        await new Promise(ok=>f.onload=ok); verify=()=>f.contentDocument.querySelector('input').value==='Draft';""",
    "session": """sessionStorage.setItem('state','working');verify=()=>sessionStorage.state==='working';""",
    "scroll": """document.body.style.height='9000px';scrollTo(0,701);verify=()=>scrollY===701;""",
    "rtc": """let a=new RTCPeerConnection(), b=new RTCPeerConnection();
        let channel=a.createDataChannel('silent'),remote;
        b.ondatachannel=e=>{remote=e.channel;remote.onmessage=e=>remote.send(e.data)};
        async function gather(peer,sdp) {
          await peer.setLocalDescription(sdp);
          if(peer.iceGatheringState!=='complete') await new Promise(ok=>peer.onicegatheringstatechange=()=>{
            if(peer.iceGatheringState==='complete')ok()});
          return peer.localDescription;
        }
        await b.setRemoteDescription(await gather(a,await a.createOffer()));
        await a.setRemoteDescription(await gather(b,await b.createAnswer()));
        if(channel.readyState!=='open')await new Promise(ok=>channel.onopen=ok);
        verify=async()=>{let result=new Promise(ok=>channel.onmessage=e=>ok(e.data==='ping'));
          channel.send('ping');return result};""",
    "media": """let video=document.body.appendChild(document.createElement('video'));
        video.muted=true;let canvas=document.createElement('canvas');
        let ctx=canvas.getContext('2d'); setInterval(()=>ctx.fillRect(0,0,1,1),100);
        video.srcObject=canvas.captureStream(10); await video.play();
        verify=()=>!video.paused && video.readyState>=2 && video.currentTime>0;""",
    "audio": """let player=new Audio('/tone.wav');player.loop=true;
        document.body.append(player);
        for (const event of ['play','pause','ended','error']) player.addEventListener(event,()=>{
          fetch('/audio-event/'+event+'-'+player.currentTime.toFixed(2));
        });
        await new Promise((ok,fail)=>{window.playTestTrack=()=>player.play().then(ok,fail);
          document.title='Start audio'});
        verify=()=>!player.paused && player.currentTime>0;""",
    "webaudio": """const ctx = new AudioContext(), oscillator = ctx.createOscillator(), gain = ctx.createGain();
        gain.gain.value=0; oscillator.connect(gain).connect(ctx.destination); oscillator.start();
        await new Promise((ok,fail)=>{window.playTestTrack=()=>ctx.resume().then(ok,fail);
          document.title='Start audio'}); verify=()=>ctx.state==='running' && ctx.currentTime>0;""",
    "fairness": "let f=document.body.appendChild(document.createElement('textarea')); f.value='Draft';",
    "exception": "", "reselect": "verify=()=>true", "split": "", "history": "", "idle": """window.memory=new Uint8Array(64*1024*1024);window.memory.fill(31);
        document.body.insertAdjacentHTML('beforeend','<input type=range min=2 max=8><input type=color><select><option disabled>first</option><option>second</option></select>');"""
}


class Pages(BaseHTTPRequestHandler):
    def do_GET(self):
        key = self.path.strip("/")
        self.send_response(200)
        if key == "tone.wav":
            audio = io.BytesIO()
            with wave.open(audio, "wb") as tone:
                tone.setparams((1, 2, 8000, 0, "NONE", ""))
                tone.writeframes(b"\0\0" * (8000 * 45))
            data = audio.getvalue()
            self.send_header("Content-Type", "audio/wav")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if key == "field":
            html = "<input><script>document.querySelector('input').value='Draft'</script>"
        elif key.startswith("audio-event/"):
            self.server.audio_events.append(key)
            html = ""
        elif key == "verify":
            html = "yes" if (self.server.profile / "validate").exists() else "no"
        elif key in pages:
            self.server.loads += 1
            title = "awake" if self.server.loads > 1 else "ready"
            html = """<title>preparing</title><body><script>(async()=>{
              let verify; %s
              document.title='%s';
              if(verify) {let timer=setInterval(async()=>{
                if(await (await fetch('/verify')).text()==='yes'){
                  clearInterval(timer);document.title=await verify()?'intact':'lost';
                }},200);}
            })().catch(e=>document.title=e.name)</script>""" % (pages[key], title)
        else:
            html = f"<title>{key if key in ('first','front','next','plain') else 'other'}</title>"
        self.wfile.write(html.encode())

    def log_message(self, *_):
        pass


def renderer_rss(parent):
    records = subprocess.check_output(["ps", "-axo", "pid=,ppid=,rss=,command="], text=True)
    processes = [line.split(None, 3) for line in records.splitlines()]
    descendants = {parent}
    while True:
        children = {int(pid) for pid, ppid, _, _ in processes if int(ppid) in descendants}
        if children <= descendants:
            break
        descendants.update(children)
    return sum(int(rss) for pid, _, rss, command in processes if int(pid) in descendants and "--type=renderer" in command)


def play_audio_track(port, url):
    # Send the gesture to the one isolated Chromium target, independently of
    # the user's foreground window. Close the inspector before the idle probe.
    script = """
      const [port,url] = process.argv.slice(1);
      const targets = await (await fetch('http://127.0.0.1:'+port+'/json/list')).json();
      const socket = new WebSocket(targets.find(t=>t.url===url).webSocketDebuggerUrl);
      await new Promise((ok,fail)=>{socket.onopen=ok;socket.onerror=fail});
      const done = new Promise((ok,fail)=>{socket.onmessage=e=>{
        const msg=JSON.parse(e.data);if(msg.id!==1)return;
        const error=msg.error || msg.result?.exceptionDetails;
        if(error)fail(Error(JSON.stringify(error)));else ok();
      }});
      socket.send(JSON.stringify({id:1,method:'Runtime.evaluate',
        params:{expression:'void window.playTestTrack()',userGesture:true}}));
      await done;
      socket.close(); process.exit(0);
    """
    subprocess.run(["node", "--input-type=module", "-e", script, str(port), url], check=True, timeout=8)


def exercise(app, key, server, profile):
    server.profile, server.loads, server.audio_events = profile, 0, []
    env = {**os.environ, "BROWSER_NATIVE_TEST_DATA": str(profile),
           "BROWSER_SAVER_ORIGIN": f"http://127.0.0.1:{server.server_port}", "BROWSER_SAVER_SCENARIO": key}
    debug_port = None
    if key in ("audio", "webaudio"):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            debug_port = listener.getsockname()[1]
        env["BROWSER_NATIVE_DEBUG_PORT"] = str(debug_port)
    app_process = subprocess.Popen([app], env=env)
    samples = {}
    try:
        deadline = time.monotonic() + 65
        while app_process.poll() is None and time.monotonic() < deadline:
            if debug_port and (profile / "play").exists():
                play_audio_track(debug_port, env["BROWSER_SAVER_ORIGIN"]+"/"+key)
                debug_port = None
            if key == "idle":
                for mark in ("before", "after"):
                    if mark not in samples and (profile / mark).exists():
                        samples[mark] = renderer_rss(app_process.pid)
            time.sleep(.1)
        if app_process.wait(timeout=1) != 0:
            if key == "audio":
                print("Playback events:", server.audio_events, flush=True)
            for log in profile.glob("Chromium/Diagnostics/*/process.log"):
                lines = log.read_text(errors="replace").splitlines()
                print("\n".join(line for line in lines if "Fatal error:" in line or "Precondition failed" in line), flush=True)
            raise RuntimeError(f"native test failed: {key}")
    finally:
        if app_process.poll() is None:
            app_process.kill()
            app_process.wait()
    if key not in ("history", "idle", "exception") and server.loads != 1:
        raise AssertionError(f"{key}: a protected page was reloaded")
    if len(samples) == 2:
        print(f"Renderer RSS, 64 MiB fixture: {samples['before']/1024:.1f} → {samples['after']/1024:.1f} MiB", flush=True)


with tempfile.TemporaryDirectory(prefix="tab-saver-check-", dir=build) as temp, ThreadingHTTPServer(("127.0.0.1", 0), Pages) as server:
    root = Path(temp)
    app = root / "Arc Reborn.app"
    subprocess.run(["cp", "-cR", build / app.name, app], check=True)
    plist = app / "Contents/Info.plist"
    info = plistlib.loads(plist.read_bytes())
    info["CFBundleIdentifier"] = "local.browser.tab-saver-test"
    plist.write_bytes(plistlib.dumps(info))
    exe = app / "Contents/MacOS/Arc Reborn"
    sources = sorted(s for s in (native/"Sources").glob("*.swift") if s.name != "main.swift")
    subprocess.run(["xcrun", "swiftc", "-j", "6", "-Onone", "-swift-version", "5", "-target", "arm64-apple-macosx13.0",
                    "-import-objc-header", native/"Bridge/BrowserBridge.h", *sources, native/"Tests/TabMemorySaverHarness.swift",
                    build/"cmake/libBrowserBridge.a", build/"cmake/libcef_dll_wrapper/libcef_dll_wrapper.a", "-lc++",
                    "-framework", "Cocoa", "-framework", "IOSurface", "-framework", "Security", "-framework", "SecurityInterface",
                    "-F", native/"vendor/sparkle-2.10.1", "-framework", "Sparkle", "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks", "-Xlinker", "-ObjC", "-o", exe], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", app], check=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    for key in sys.argv[1:] or ["idle", "history", "rtc", "media", "audio", "webaudio", "draft", "frame", "editor", "session", "scroll", "split", "reselect", "fairness", "exception"]:
        exercise(exe, key, server, root/key)
