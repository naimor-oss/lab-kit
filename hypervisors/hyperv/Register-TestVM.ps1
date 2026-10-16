#Requires -Modules Hyper-V
<#
.SYNOPSIS
    Register a VM whose files are already in their final place (Import-VM
    -Register), optionally starting it.

.DESCRIPTION
    For a VM folder produced elsewhere, e.g. an exported appliance build
    copied to the lab share: the VM runs from those files where they are,
    with no copy. -Path is the VM folder (with "Virtual Machines\*.vmcx")
    or the .vmcx file itself.

    This registers one VM with its own ID. It cannot make several VMs from
    one folder; for that, publish a base (Publish-BaseVhdx.ps1) and use
    New-TestVM.ps1.

    -SwitchName reconnects the VM's adapters when the switch it was exported
    with doesn't exist here. -Disposable tags it so Remove-TestVM.ps1 may
    delete it later (only if the folder is <VMRoot>\<Name>).

    Needs Hyper-V rights only (elevated, or a member of Hyper-V Administrators).

.EXAMPLE
    Register-TestVM.ps1 -Path D:\Lab\VMs\appliance-0.6.0 -SwitchName Lab-NAT -Start
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$Path,
    [string]$SwitchName = '',
    [switch]$Disposable,
    [switch]$Start
)
$ErrorActionPreference = 'Stop'

$folder = if ($Path -like '*.vmcx') { Split-Path -Parent (Split-Path -Parent $Path) } else { $Path }
if ($Disposable) {
    # Lets Remove-TestVM.ps1 clean up the folder even if registering fails.
    Set-Content -LiteralPath (Join-Path $folder '.lab-kit-disposable') -Value 'registered'
}

# Registering sets each file's ACL for the VM. Without elevation (Hyper-V
# Administrators) that only works on files this user owns, and files written
# by Hyper-V itself (Export-VM) belong to SYSTEM: "Failed to set security
# info ... Access is denied". Replace those with copies this user owns. On
# ReFS the copy is a block clone and costs nothing.
$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    foreach ($f in Get-ChildItem -LiteralPath $folder -Recurse -File) {
        if ((Get-Acl -LiteralPath $f.FullName).Owner -eq $me) { continue }
        $tmp = "$($f.FullName).own"
        Copy-Item -LiteralPath $f.FullName -Destination $tmp
        Remove-Item -LiteralPath $f.FullName -Force
        Rename-Item -LiteralPath $tmp -NewName $f.Name
    }
}

$vmcx = if ($Path -like '*.vmcx') { Get-Item -LiteralPath $Path } else {
    @(Get-ChildItem -LiteralPath $Path -Recurse -Filter *.vmcx)
}
if (@($vmcx).Count -ne 1) { throw "expected one .vmcx under $Path, found $(@($vmcx).Count)" }
$vmcx = @($vmcx)[0].FullName

$report = Compare-VM -Path $vmcx -Register
foreach ($i in @($report.Incompatibilities)) {
    if ($i.Source -is [Microsoft.HyperV.PowerShell.VMNetworkAdapter] -and $SwitchName) {
        $i.Source | Connect-VMNetworkAdapter -SwitchName $SwitchName
    } else {
        throw "cannot register $vmcx as is: $($i.Message)"
    }
}
$vm = Import-VM -CompatibilityReport $report
if ($Disposable) {
    $vm | Set-VM -Notes ("lab-kit:disposable registered=$((Get-Date).ToString('s')) " + $vm.Notes).Trim()
}
$vm | Set-VM -AutomaticCheckpointsEnabled $false
# Export-VM doesn't carry ISO files, so their paths may point nowhere here.
foreach ($d in @($vm | Get-VMDvdDrive)) {
    if ($d.Path -and -not (Test-Path -LiteralPath $d.Path)) {
        Write-Warning "ejecting missing media $($d.Path)"
        $d | Set-VMDvdDrive -Path $null
    }
}
if ($Start) { $vm | Start-VM }
'VM {0} registered from {1} state={2}' -f $vm.Name, $vmcx, (Get-VM -Id $vm.Id).State
