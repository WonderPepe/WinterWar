"""Browser test of the Ctrl+W guard (after exporting to export/web/):
    python3 tools/web_guard_test.py
Checks in headless Chromium: no "Leave site?" warning in the menu, the warning is on during a
battle (closing the tab then fires `beforeunload`), and going fullscreen shows the
"hold Esc" notice (screenshot tools/shots/web_fullscreen_notice.png).
Real Ctrl+W can't be pressed from a test (the browser handles it, not the page) – try it by hand."""
import asyncio, functools, http.server, os, threading, time
from playwright.async_api import async_playwright

ROOT = os.path.join(os.getcwd(), "export", "web")
SHOTS = os.path.join(os.getcwd(), "tools", "shots")
PORT = 8062
fails = 0

def check(cond, msg):
    global fails
    print(("PASS  " if cond else "FAIL  ") + msg)
    if not cond:
        fails += 1

def serve():
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=ROOT)
    handler.log_message = lambda *a: None
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler).serve_forever()

async def wait_js(page, expr, limit):
    t0 = time.time()
    while time.time() - t0 < limit:
        if await page.evaluate(expr):
            return True
        await asyncio.sleep(0.5)
    return False

async def main():
    threading.Thread(target=serve, daemon=True).start()
    os.makedirs(SHOTS, exist_ok=True)
    errors = []
    async with async_playwright() as p:
        browser = await p.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader",
                                                "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        page = await browser.new_page(viewport={"width": 960, "height": 540})
        page.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        page.on("pageerror", lambda e: errors.append(str(e)))
        dialogs = []
        async def on_dialog(d):
            dialogs.append(d.type)
            await d.dismiss()  # "Stay on page"
        page.on("dialog", on_dialog)
        await page.goto(f"http://127.0.0.1:{PORT}/index.html")
        check(await page.evaluate("window.summaLeaveWarning === false"), "page script loaded, no warning in the menu")
        check(await page.evaluate("!!(navigator.keyboard && navigator.keyboard.lock)"), "Keyboard Lock available (Chromium)")
        await asyncio.sleep(10)
        # Fullscreen from a click (browsers need one), like ticking the box in Settings.
        await page.mouse.click(480, 470)
        await page.evaluate("document.documentElement.requestFullscreen().catch(() => {})")
        full = await wait_js(page, "!!document.fullscreenElement", 5)
        check(full, "fullscreen entered")
        shown = await wait_js(page, "window.summaFullscreenNotices === 1", 10)
        check(shown, "the 'hold Esc to leave fullscreen' notice is shown")
        await asyncio.sleep(1.5)
        await page.screenshot(path=os.path.join(SHOTS, "web_fullscreen_notice.png"), timeout=180000)
        await page.evaluate("document.exitFullscreen().catch(() => {})")
        await asyncio.sleep(1)
        await page.mouse.click(480, 197)  # Single Player (960x540 layout)
        on = await wait_js(page, "window.summaLeaveWarning === true", 120)
        check(on, "battle running → leave warning on")
        await page.mouse.click(480, 300)  # "Click to start the battle" (also the user activation)
        await page.keyboard.press("w")
        await asyncio.sleep(1)
        # Leaving the page (closing the tab, Ctrl+W, F5) – a test can only do it by navigating.
        try:
            await page.goto("about:blank", timeout=30000)  # (slow software rendering)
        except Exception:
            pass  # 'Stay on page' stops the navigation
        await asyncio.sleep(1)
        check("beforeunload" in dialogs, "leaving the page asks 'Leave site?' (%s)" % dialogs)
        check(page.url.endswith("index.html"), "…and 'Stay' keeps the game open")
        await browser.close()
    real = [e for e in errors if "Leave site" not in e]
    check(not real, "no console errors %s" % real[:3])
    print("RESULT:", "OK" if fails == 0 else "FAILED (%d)" % fails)

asyncio.run(main())
