#Requires -Modules Hyper-V
<#
.SYNOPSIS
    Create (and start) a disposable test VM from a sealed base VHDX.

.DESCRIPTION
    The VM gets its own disk made from -BaseVhdx, never the base itself:
      Copy          full copy. On ReFS (e.g. a Windows Dev Drive) the copy is
                    a block clone and takes well under a second.
      Differencing  child disk with -BaseVhdx as parent. Fast on any file
                    system, but the base must then never move or change.
      Auto          (default) Copy on ReFS, Differencing otherwise.

    The base should be sealed (bin/lab-vm seal, docs/disposable-vms.md): no
    machine-id, no SSH host keys, cloud-init enabled. Each VM then takes its
    identity (hostname, user, key) from its own -SeedIso on first boot.

    The VM is tagged as disposable in its Notes, which Remove-TestVM.ps1
    requires before it deletes anything. Automatic checkpoints are off.
    Prints one line: "VM <name> mac=<MAC> disk=<mode> seconds=<n>".

    Needs Hyper-V rights only (elevated, or a member of Hyper-V Administrators).

.EXAMPLE
    New-TestVM.ps1 -Name t1 -BaseVhdx D:\Lab\bases\debian-13-blank-20261015.vhdx `
        -VMRoot D:\Lab\VMs -SwitchName Lab-NAT -SeedIso D:\Lab\seeds\t1-seed.iso
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Name,
    [Parameter(Mandatory)] [string]$BaseVhdx,
    [Parameter(Mandatory)] [string]$VMRoot,
    [Parameter(Mandatory)] [string]$SwitchName,
    [string]$SeedIso = '',
    [int]   $MemoryMB = 2048,
    [int]   $VCpu = 2,
    [int]   $DiskGB = 0,          # grow the VM's disk to this size; 0 = keep the base size
    [string]$MacAddress = '',     # static MAC (any separators); default dynamic
    [ValidateSet('Auto', 'Copy', 'Differencing')] [string]$DiskMode = 'Auto',
    [switch]$NoStart
)
$ErrorActionPreference = 'Stop'
$started = Get-Date

if (Get-VM | Where-Object Name -eq $Name) { throw "VM '$Name' already exists" }
if (-not (Test-Path -LiteralPath $BaseVhdx)) { throw "base VHDX not found: $BaseVhdx" }
if ($SeedIso -and -not (Test-Path -LiteralPath $SeedIso)) { throw "seed ISO not found: $SeedIso" }
Get-VMSwitch -Name $SwitchName | Out-Null

$dir = Join-Path $VMRoot $Name
if (Test-Path -LiteralPath $dir) { throw "folder already exists: $dir" }
New-Item -ItemType Directory -Path $dir | Out-Null
# Lets Remove-TestVM.ps1 clean up this folder even if the VM never got created.
Set-Content -LiteralPath (Join-Path $dir '.lab-kit-disposable') -Value $Name
$disk = Join-Path $dir "$Name.vhdx"

if ($DiskMode -eq 'Auto') {
    $fs = (Get-Volume -FilePath $dir).FileSystemType
    $DiskMode = if ($fs -eq 'ReFS') { 'Copy' } else { 'Differencing' }
}
try {
    if ($DiskMode -eq 'Copy') {
        Copy-Item -LiteralPath $BaseVhdx -Destination $disk
        # A published base is read-only; the VM's copy must not be.
        Set-ItemProperty -LiteralPath $disk -Name IsReadOnly -Value $false
    } else {
        New-VHD -Path $disk -ParentPath $BaseVhdx -Differencing | Out-Null
    }
    if ($DiskGB -gt 0) { Resize-VHD -Path $disk -SizeBytes ($DiskGB * 1GB) }

    $vm = New-VM -Name $Name -Generation 2 -MemoryStartupBytes ($MemoryMB * 1MB) `
        -SwitchName $SwitchName -VHDPath $disk -Path $VMRoot
    $vm | Set-VMProcessor -Count $VCpu
    $vm | Set-VMMemory -DynamicMemoryEnabled $false
    $vm | Set-VMFirmware -EnableSecureBoot Off -FirstBootDevice ($vm | Get-VMHardDiskDrive)
    if ($SeedIso) {
        # Keep the VM's own copy, so the shared seed folder can be cleaned up.
        $seed = Join-Path $dir 'seed.iso'
        Copy-Item -LiteralPath $SeedIso -Destination $seed
        $vm | Add-VMDvdDrive -Path $seed
    }
    if ($MacAddress) {
        $hex = ($MacAddress -replace '[:-]', '').ToUpperInvariant()
        if ($hex -notmatch '^[0-9A-F]{12}$') { throw "-MacAddress '$MacAddress' is not a MAC address" }
        $vm | Get-VMNetworkAdapter | Set-VMNetworkAdapter -StaticMacAddress $hex
    }
    $vm | Enable-VMIntegrationService -Name 'Guest Service Interface'
    $vm | Set-VM -CheckpointType Standard -AutomaticCheckpointsEnabled $false `
        -AutomaticStopAction TurnOff -AutomaticStartAction Nothing `
        -Notes "lab-kit:disposable base=$BaseVhdx disk=$DiskMode created=$($started.ToString('s'))"
} catch {
    if (Get-VM | Where-Object Name -eq $Name) { Remove-VM -Name $Name -Force }
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    throw
}

if (-not $NoStart) { Start-VM -Name $Name }
# A dynamic MAC is assigned at first start; until then it reads all zeros.
$mac = (Get-VMNetworkAdapter -VMName $Name | Select-Object -First 1).MacAddress
'VM {0} mac={1} disk={2} seconds={3:N1}' -f $Name, $mac, $DiskMode, ((Get-Date) - $started).TotalSeconds
