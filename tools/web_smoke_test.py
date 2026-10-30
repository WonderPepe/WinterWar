"""Smoke test of the web export in headless Chromium (software WebGL).
Usage (from the project folder, after exporting to export/web/):
    python3 tools/web_smoke_test.py
Starts a local web server, opens the game, checks the engine starts without errors,
clicks Single Player and saves screenshots to tools/shots/web_*.png.
Software WebGL is very slow, so it only checks that things work - not performance."""
import asyncio, functools, http.server, os, threading, time
from playwright.async_api import async_playwright

ROOT = os.path.join(os.getcwd(), "export", "web")
SHOTS = os.path.join(os.getcwd(), "tools", "shots")
PORT = 8061

def serve():
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=ROOT)
    handler.log_message = lambda *a: None
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler).serve_forever()

async def main():
    threading.Thread(target=serve, daemon=True).start()
    os.makedirs(SHOTS, exist_ok=True)
    errors, started = [], False
    async with async_playwright() as p:
        browser = await p.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader",
                                                "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        page = await browser.new_page(viewport={"width": 960, "height": 540})
        def on_console(m):
            nonlocal started
            if "Godot Engine" in m.text: started = True
            if m.type == "error": errors.append(m.text)
        page.on("console", on_console)
        page.on("pageerror", lambda e: errors.append(str(e)))
        t0 = time.time()
        await page.goto(f"http://127.0.0.1:{PORT}/index.html")
        while not started and time.time() - t0 < 60:
            await asyncio.sleep(0.25)
        print(f"engine started: {started} ({time.time() - t0:.1f} s)")
        await asyncio.sleep(5)
        await page.screenshot(path=os.path.join(SHOTS, "web_menu.png"))
        await page.mouse.click(480, 197)  # Single Player (960x540 layout)
        await asyncio.sleep(20)
        await page.screenshot(path=os.path.join(SHOTS, "web_game.png"), timeout=180000)
        await asyncio.sleep(25)  # the software renderer is slow: look again later
        await page.screenshot(path=os.path.join(SHOTS, "web_game_later.png"), timeout=180000)
        await browser.close()
    print("console errors:", errors if errors else "none")
    print("RESULT:", "OK" if started and not errors else "FAILED")

asyncio.run(main())
