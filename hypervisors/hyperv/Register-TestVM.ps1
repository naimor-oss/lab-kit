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
if ($Start) { $vm | Start-VM }
'VM {0} registered from {1} state={2}' -f $vm.Name, $vmcx, (Get-VM -Id $vm.Id).State
