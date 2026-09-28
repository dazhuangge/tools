# ==========================================
# Proxy Control Function
# ==========================================
function pxy {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('on', 'off', 'status', 'test')]
        [string]$Action = 'status',

        [Parameter(Position = 1)]
        [string]$Addr = 'http://127.0.0.1:7897'
    )

    switch ($Action) {
        'on' {
            $env:HTTP_PROXY  = $Addr
            $env:HTTPS_PROXY = $Addr
            $env:ALL_PROXY   = $Addr
            try {
                [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy($Addr)
            } catch {}
            Write-Host "[OK] 代理已开启: $Addr" -ForegroundColor Green
        }
        'off' {
            $env:HTTP_PROXY  = $null
            $env:HTTPS_PROXY = $null
            $env:ALL_PROXY   = $null
            try {
                [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy
            } catch {}
            Write-Host "[*] 代理已关闭 (已恢复直连状态)" -ForegroundColor Yellow
        }
        'status' {
            if ($env:HTTP_PROXY) {
                Write-Host "当前代理地址: $env:HTTP_PROXY" -ForegroundColor Cyan
            } else {
                Write-Host "当前未设置代理 (直连状态)" -ForegroundColor Gray
            }
        }
        'test' {
            try {
                $irmParams = @{
                    Uri         = 'https://httpbin.org/ip'
                    TimeoutSec  = 5
                    ErrorAction = 'Stop'
                }
                if ($env:HTTPS_PROXY) {
                    $irmParams['Proxy'] = $env:HTTPS_PROXY
                } elseif ($env:HTTP_PROXY) {
                    $irmParams['Proxy'] = $env:HTTP_PROXY
                }
                $response = Invoke-RestMethod @irmParams
                $ip = if ($response.origin) { $response.origin } else { $response }
                Write-Host "出口 IP: $ip" -ForegroundColor Green
            } catch {
                Write-Host "请求失败: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    }
}