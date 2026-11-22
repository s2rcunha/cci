$ErrorActionPreference = "Stop"

# O acesso pela rede local exige escuta em todas as interfaces e, no Windows,
# normalmente uma permissao elevada para registrar o prefixo HTTP do HttpListener.
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argumentos
    exit
}

$root = (Resolve-Path $PSScriptRoot).Path
$rootPrefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$listener = New-Object System.Net.HttpListener
$prefix = "http://+:8765/"
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
    Write-Host "`nSIMULADOR CCI - ACESSO PELA REDE WI-FI" -ForegroundColor Green
    Write-Host "No computador: http://127.0.0.1:8765/"
    Write-Host "No smartphone, conectado a mesma rede Wi-Fi, use um dos enderecos abaixo:" -ForegroundColor Cyan

    $ips = @()
    try {
        $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -ne "127.0.0.1" -and $_.IPAddress -notlike "169.254.*" -and $_.AddressState -eq "Preferred" } |
            Select-Object InterfaceAlias, IPAddress)
    } catch {
        $ips = @()
    }
    if ($ips.Count -gt 0) {
        foreach ($item in $ips) {
            Write-Host ("  http://{0}:8765/  ({1})" -f $item.IPAddress, $item.InterfaceAlias) -ForegroundColor Yellow
        }
    } else {
        Write-Host "  Nao foi possivel detectar o IP automaticamente. Consulte o IPv4 da conexao Wi-Fi com o comando ipconfig." -ForegroundColor Yellow
    }

    Write-Host "`nMantenha esta janela aberta. Para encerrar, pressione Ctrl+C." -ForegroundColor Gray
    Start-Process "http://127.0.0.1:8765/"

    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            $relative = [Uri]::UnescapeDataString($context.Request.Url.AbsolutePath.TrimStart('/'))
            if ([string]::IsNullOrWhiteSpace($relative)) { $relative = "index.html" }
            $relative = $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
            $file = [IO.Path]::GetFullPath((Join-Path $root $relative))

            if (-not $file.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $file -PathType Leaf)) {
                $context.Response.StatusCode = 404
                $bytes = [Text.Encoding]::UTF8.GetBytes("404 - Arquivo nao encontrado")
                $context.Response.ContentType = "text/plain; charset=utf-8"
            } else {
                $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
                $context.Response.ContentType = switch ($ext) {
                    ".html" { "text/html; charset=utf-8" }
                    ".js"   { "text/javascript; charset=utf-8" }
                    ".css"  { "text/css; charset=utf-8" }
                    ".json" { "application/json; charset=utf-8" }
                    ".svg"  { "image/svg+xml" }
                    ".glb"  { "model/gltf-binary" }
                    ".gltf" { "model/gltf+json" }
                    ".txt"  { "text/plain; charset=utf-8" }
                    default { "application/octet-stream" }
                }
                $bytes = [IO.File]::ReadAllBytes($file)
                $context.Response.StatusCode = 200
            }
            $context.Response.ContentLength64 = $bytes.Length
            $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch {
            try { $context.Response.StatusCode = 500 } catch { }
        } finally {
            try { $context.Response.OutputStream.Close() } catch { }
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
