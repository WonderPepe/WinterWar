# Tiny local web server for testing the web export (Windows PowerShell, no install needed).
# Started by play_in_browser.bat. Serves the files next to this script at http://localhost:8060/
# and opens the game in your default browser. Close the window to stop the server.
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$port = 8060
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
try { $listener.Start() } catch { Write-Host "Could not start the server on port $port. Is it already running?"; Read-Host "Press Enter to close"; exit 1 }
Write-Host "Winter War: Summa - serving $root"
Write-Host "Game: http://localhost:$port/index.html   (close this window to stop)"
Start-Process "http://localhost:$port/index.html"
$mime = @{
    ".html" = "text/html"; ".js" = "application/javascript"; ".wasm" = "application/wasm";
    ".pck" = "application/octet-stream"; ".png" = "image/png"; ".ico" = "image/x-icon"; ".json" = "application/json"
}
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
        $name = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
        if ($name -eq "") { $name = "index.html" }
        $file = [IO.Path]::GetFullPath((Join-Path $root $name))
        if ($file.StartsWith($root) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
            $bytes = [IO.File]::ReadAllBytes($file)
            $ext = [IO.Path]::GetExtension($file).ToLower()
            if ($mime.ContainsKey($ext)) { $ctx.Response.ContentType = $mime[$ext] } else { $ctx.Response.ContentType = "application/octet-stream" }
            $ctx.Response.ContentLength64 = $bytes.Length
            $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $ctx.Response.StatusCode = 404
        }
    } catch {
        Write-Host "Error: $_"
    } finally {
        $ctx.Response.Close()
    }
}
