# 本地静态服务器（纯 TcpListener，无需安装、无需管理员）
# 用法： powershell -ExecutionPolicy Bypass -File .\start-viewer.ps1
param(
  [int]$Port = 8000,
  [string]$Page = 'pushplus-viewer.html',
  [switch]$NoOpen
)

$ErrorActionPreference = 'Stop'
$dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

$types = @{
  '.html'='text/html; charset=utf-8'; '.htm'='text/html; charset=utf-8'
  '.js'='application/javascript; charset=utf-8'; '.css'='text/css; charset=utf-8'
  '.json'='application/json; charset=utf-8'; '.svg'='image/svg+xml'
  '.png'='image/png'; '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.gif'='image/gif'
  '.ico'='image/x-icon'; '.txt'='text/plain; charset=utf-8'
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
$listener.Start()
$url = "http://localhost:$Port/$Page"
Write-Host ""
Write-Host "  PUSHplus 查看器已启动" -ForegroundColor Green
Write-Host "  地址 : $url"
Write-Host "  目录 : $dir"
Write-Host "  停止 : 按 Ctrl+C 或关闭本窗口"
Write-Host ""
if (-not $NoOpen) { Start-Process $url }

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII)
      $requestLine = $reader.ReadLine()
      if ([string]::IsNullOrWhiteSpace($requestLine)) { $client.Close(); continue }
      while ($true) {
        $line = $reader.ReadLine()
        if ([string]::IsNullOrEmpty($line)) { break }
        if ($null -eq $line) { break }
      }

      $parts = $requestLine.Split(' ')
      $method = if ($parts.Length -ge 1) { $parts[0] } else { 'GET' }
      $rawPath = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
      $path = $rawPath.Split('?')[0]
      $path = [System.Uri]::UnescapeDataString($path).TrimStart('/')
      if ([string]::IsNullOrWhiteSpace($path)) { $path = $Page }

      $target = [System.IO.Path]::GetFullPath((Join-Path $dir $path))
      $rootFull = [System.IO.Path]::GetFullPath($dir)

      $status = '200 OK'; $ctype = 'application/octet-stream'; $body = $null
      if ($method -eq 'OPTIONS') {
        # 允许浏览器从公网页面（如 github.com）直接读取本地文件，需 CORS + 私有网络预检
        $status = '204 No Content'; $ctype = 'text/plain'; $body = [byte[]]::new(0)
      } elseif (-not $target.StartsWith($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
        $status = '403 Forbidden'
      } elseif (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        $status = '404 Not Found'; $body = [System.Text.Encoding]::UTF8.GetBytes('404 Not Found')
      } else {
        $ext = [System.IO.Path]::GetExtension($target).ToLower()
        if ($types.ContainsKey($ext)) { $ctype = $types[$ext] }
        $body = [System.IO.File]::ReadAllBytes($target)
      }

      if ($null -eq $body) { $body = [byte[]]::new(0) }

      $head = "HTTP/1.1 $status`r`n" +
              "Content-Type: $ctype`r`n" +
              "Content-Length: $($body.Length)`r`n" +
              "Cache-Control: no-store`r`n" +
              "Access-Control-Allow-Origin: *`r`n" +
              "Access-Control-Allow-Methods: GET, OPTIONS`r`n" +
              "Access-Control-Allow-Headers: *`r`n" +
              "Access-Control-Allow-Private-Network: true`r`n" +
              "Connection: close`r`n`r`n"
      $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
      $stream.Write($hb, 0, $hb.Length)
      if ($body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
      $stream.Flush()
    } catch {
      Write-Host "请求处理异常: $($_.Exception.Message)" -ForegroundColor Yellow
    } finally {
      try { $client.Close() } catch {}
    }
  }
} finally {
  $listener.Stop()
}
