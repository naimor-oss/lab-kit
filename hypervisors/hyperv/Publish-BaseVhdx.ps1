#Requires -Modules Hyper-V
<#
.SYNOPSIS
    Publish a powered-off, sealed VM's disk as a standalone read-only base VHDX.

.DESCRIPTION
    Writes the VM's current disk (its whole differencing chain, merged) to
    -Destination as a dynamic VHDX and marks it read-only. New-TestVM.ps1
    then makes test VMs from it.

    A published base is never overwritten or moved: VMs made with
    -DiskMode Differencing reference it by path. Publish a new, dated file
    instead (docs/disposable-vms.md) and delete old ones once no VM uses them.

    The VM must be Off, and should have been sealed first (bin/lab-vm seal);
    booting it again after sealing would give it an identity again.

    Needs Hyper-V rights only (elevated, or a member of Hyper-V Administrators).

.EXAMPLE
    Publish-BaseVhdx.ps1 -VMName build-blank -Destination D:\Lab\bases\debian-13-blank-20261015.vhdx
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$VMName,
    [Parameter(Mandatory)] [string]$Destination
)
$ErrorActionPreference = 'Stop'
$started = Get-Date

$vm = Get-VM -Name $VMName
if ($vm.State -ne 'Off') { throw "VM '$VMName' is $($vm.State); seal it and let it power off first" }
if (Test-Path -LiteralPath $Destination) { throw "$Destination exists; publish under a new name" }
$drives = @($vm | Get-VMHardDiskDrive)
if ($drives.Count -ne 1) { throw "VM '$VMName' has $($drives.Count) disks; expected one" }

New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
$tmp = "$Destination.partial"
Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
# Convert-VHD reads through the differencing chain, so the result stands alone.
Convert-VHD -Path $drives[0].Path -DestinationPath $tmp -VHDType Dynamic
Move-Item -LiteralPath $tmp -Destination $Destination
Set-ItemProperty -LiteralPath $Destination -Name IsReadOnly -Value $true

$v = Get-VHD -Path $Destination
'published {0} size={1:N1}GB file={2:N2}GB seconds={3:N1}' -f $Destination, ($v.Size / 1GB), ($v.FileSize / 1GB), ((Get-Date) - $started).TotalSeconds
