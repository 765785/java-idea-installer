[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Directory,

    [int]$Port = 8765,

    [Parameter(Mandatory)]
    [string]$Token
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path -LiteralPath $Directory).Path
$listener = [System.Net.HttpListener]::new()
$prefix = "http://127.0.0.1:$Port/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    exit 1
}

$deadline = [DateTime]::UtcNow.AddMinutes(20)
while ($listener.IsListening -and [DateTime]::UtcNow -lt $deadline) {
    try {
        $context = $listener.GetContext()
        $relative = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart("/"))
        if ([string]::IsNullOrWhiteSpace($relative)) {
            $relative = "progress.html"
        }
        if ($relative -notin @("progress.html", "progress.js", "progress.json")) {
            $context.Response.StatusCode = 404
            $context.Response.Close()
            continue
        }
        if ($relative -notin @("progress.html", "progress.js") -and $context.Request.QueryString["token"] -ne $Token) {
            $context.Response.StatusCode = 403
            $context.Response.Close()
            continue
        }

        $candidate = [System.IO.Path]::GetFullPath((Join-Path $root $relative))
        $rootPrefix = $root.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $context.Response.StatusCode = 404
            $context.Response.Close()
            continue
        }

        $extension = [System.IO.Path]::GetExtension($candidate).ToLowerInvariant()
        $contentTypes = @{
            ".html" = "text/html; charset=utf-8"
            ".js" = "text/javascript; charset=utf-8"
            ".json" = "application/json; charset=utf-8"
            ".png" = "image/png"
            ".svg" = "image/svg+xml"
            ".css" = "text/css; charset=utf-8"
        }
        if (-not $contentTypes.ContainsKey($extension)) {
            $context.Response.StatusCode = 403
            $context.Response.Close()
            continue
        }
        $context.Response.ContentType = $contentTypes[$extension]
        $context.Response.Headers["Cache-Control"] = "no-store"
        $context.Response.Headers["X-Content-Type-Options"] = "nosniff"
        $bytes = [System.IO.File]::ReadAllBytes($candidate)
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.Close()
    } catch {
        if ($listener.IsListening) {
            Start-Sleep -Milliseconds 150
        }
    }
}

$listener.Stop()
$listener.Close()
