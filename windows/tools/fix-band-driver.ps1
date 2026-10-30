# BandFace: вимикає зламаний драйверний вузол браслета (Код 10) і не дає Windows вмикати його знову.
# Запускати від імені адміністратора (краще через fix-band-driver.bat).
# Скасування:  powershell -ExecutionPolicy Bypass -File fix-band-driver.ps1 -Undo
param([switch]$Undo, [string]$Name = '*Xiaomi Smart Band*')

$ErrorActionPreference = 'Stop'
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
$deny   = Join-Path $policy 'DenyInstanceIDs'

function Get-BandNodes {
    # усі вузли PnP браслета, які Windows створила (BTHLE\..., BTHLEDEVICE\..., HID\...)
    Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
        $_.FriendlyName -like $Name -or ($_.InstanceId -match 'BTHLE' -and $_.FriendlyName -like $Name)
    }
}

if ($Undo) {
    if (Test-Path $deny) { Remove-Item $deny -Recurse -Force }
    if (Test-Path $policy) {
        Remove-ItemProperty -Path $policy -Name 'DenyInstanceIDs' -ErrorAction SilentlyContinue
        Remove-ItemProperty -Path $policy -Name 'DenyDeviceIDs' -ErrorAction SilentlyContinue
    }
    foreach ($d in Get-BandNodes) { try { Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false } catch {} }
    Write-Host 'Скасовано. Обмеження знято, пристрої увімкнено.'
    exit 0
}

$nodes = @(Get-BandNodes)
if ($nodes.Count -eq 0) {
    Write-Host 'Вузлів браслета не знайдено. Спершу підключіть браслет у програмі BandFace, потім запустіть цей скрипт.'
    exit 1
}

Write-Host 'Знайдено вузли:'
$nodes | ForEach-Object { Write-Host ('  ' + $_.Status + '  ' + $_.InstanceId) }

# вузол із помилкою — той, що має проблемний код (CM_PROB_FAILED_START = 10)
$bad = @($nodes | Where-Object { $_.Status -eq 'Error' -or $_.Problem -eq 10 -or $_.ConfigManagerErrorCode -eq 10 })
if ($bad.Count -eq 0) { Write-Host 'Вузлів із кодом 10 немає, змінювати нічого не потрібно.'; exit 0 }

New-Item -Path $deny -Force | Out-Null
New-ItemProperty -Path $policy -Name 'DenyInstanceIDs' -Value 1 -PropertyType DWord -Force | Out-Null
$i = 1
foreach ($d in $bad) {
    Write-Host ('Вимикаю: ' + $d.InstanceId)
    New-ItemProperty -Path $deny -Name ([string]$i) -Value $d.InstanceId -PropertyType String -Force | Out-Null
    $i++
    try { Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false } catch { Write-Host ('  не вдалося вимкнути: ' + $_.Exception.Message) }
}
Write-Host 'Готово. Тепер підключіть браслет у BandFace. Щоб скасувати: запустіть скрипт із параметром -Undo.'
