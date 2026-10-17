#Requires -Modules Hyper-V
<#
.SYNOPSIS
    Print a VM's state, first adapter's MAC and IPv4 as key=value lines, for
    scripts (bin/lab-vm). The IPv4 comes from Hyper-V's KVP exchange, so it
    is empty unless the guest runs hyperv-daemons.

    Needs Hyper-V rights only (elevated, or a member of Hyper-V Administrators).
#>
[CmdletBinding()]
param([Parameter(Mandatory)] [string]$Name)
$ErrorActionPreference = 'Stop'
$vm = Get-VM | Where-Object Name -eq $Name
if (-not $vm) { throw "no VM named '$Name'" }
$nic = $vm | Get-VMNetworkAdapter | Select-Object -First 1
"state=$($vm.State)"
"mac=$($nic.MacAddress)"
"ipv4=$(@($nic.IPAddresses) -match '^\d+\.\d+\.\d+\.\d+$' | Select-Object -First 1)"
"notes=$($vm.Notes)"
