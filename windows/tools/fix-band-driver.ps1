# BandFace: disables Windows service nodes created for the band (HID-over-GATT etc.) that fail with Code 10
# and stops Windows from enabling them again. Run as Administrator (use fix-band-driver.bat).
# IMPORTANT: connect the band in BandFace first (pick it in the list), then run this script while it is connected,
# because Windows creates these nodes only while the band is connected.
# Undo:  fix-band-driver.bat -Undo
param([switch]$Undo, [string]$Mac = '0434C369E3B4')

$ErrorActionPreference = 'Continue'
$policy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'
$deny   = Join-Path $policy 'DenyInstanceIDs'

function Get-Nodes {
    Get-PnpDevice | Where-Object { $_.InstanceId -match $Mac }
}
function Get-Problem($id) {
    try { (Get-PnpDeviceProperty -InstanceId $id -KeyName 'DEVPKEY_Device_ProblemCode' -ErrorAction Stop).Data } catch { '?' }
}

if ($Undo) {
    if (Test-Path $deny) { Remove-Item $deny -Recurse -Force }
    Remove-ItemProperty -Path $policy -Name 'DenyInstanceIDs' -ErrorAction SilentlyContinue
    foreach ($d in Get-Nodes) { try { Enable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false } catch {} }
    Write-Host 'Undone: restriction removed, devices enabled.'
    exit 0
}

$nodes = @(Get-Nodes)
Write-Host ('Nodes for MAC ' + $Mac + ':')
foreach ($d in $nodes) {
    Write-Host ('  class=' + $d.Class + ' status=' + $d.Status + ' problem=' + (Get-Problem $d.InstanceId))
    Write-Host ('    ' + $d.InstanceId)
}

# service nodes = everything except the two base nodes of the device itself
$targets = @($nodes | Where-Object { $_.InstanceId -notmatch '^(BTHENUM|BTHLE)\\DEV_' })
if ($targets.Count -eq 0) {
    Write-Host ''
    Write-Host 'No service nodes yet. Connect the band in BandFace (pick it in the list), then run this script again while it is connected.'
    exit 1
}

New-Item -Path $deny -Force | Out-Null
New-ItemProperty -Path $policy -Name 'DenyInstanceIDs' -Value 1 -PropertyType DWord -Force | Out-Null
$i = 1
foreach ($d in $targets) {
    Write-Host ('Disabling: ' + $d.InstanceId)
    New-ItemProperty -Path $deny -Name ([string]$i) -Value $d.InstanceId -PropertyType String -Force | Out-Null
    $i++
    try { Disable-PnpDevice -InstanceId $d.InstanceId -Confirm:$false } catch { Write-Host ('  failed: ' + $_.Exception.Message) }
}
Write-Host 'Done. Now try installing a watch face in BandFace. Undo: fix-band-driver.bat -Undo'
