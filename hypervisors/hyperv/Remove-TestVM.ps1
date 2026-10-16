#Requires -Modules Hyper-V
<#
.SYNOPSIS
    Turn off and delete a disposable test VM made by New-TestVM.ps1.

.DESCRIPTION
    Refuses any VM whose Notes lack the "lab-kit:disposable" tag, so a typo
    can't delete a VM someone cares about. Deletes the VM and its own folder
    <VMRoot>\<Name> (disk, seed copy, config), and nothing else: never the
    base VHDX it was made from. A folder left without its VM is deleted only
    if it holds New-TestVM.ps1's marker file.

    Needs Hyper-V rights only (elevated, or a member of Hyper-V Administrators).

.EXAMPLE
    Remove-TestVM.ps1 -Name t1 -VMRoot D:\Lab\VMs
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string[]]$Name,
    [Parameter(Mandatory)] [string]$VMRoot
)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $VMRoot).Path.TrimEnd('\')
# powershell.exe -File passes "a,b" as one string.
$Name = @($Name | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

foreach ($n in $Name) {
    # Not Get-VM -Name -ErrorAction SilentlyContinue: that also hides "no
    # permission", which would look like "no such VM".
    $vm = Get-VM | Where-Object Name -eq $n
    $dir = Join-Path $root $n
    if ($vm) {
        if ($vm.Notes -notmatch '(^|\s)lab-kit:disposable(\s|$)') {
            throw "VM '$n' is not tagged lab-kit:disposable; not removing it"
        }
        if ($vm.Path.TrimEnd('\') -ne $dir) {
            throw "VM '$n' lives in $($vm.Path), not under $root; not removing it"
        }
        if ($vm.State -ne 'Off') { $vm | Stop-VM -TurnOff -Force }
        $vm | Remove-VM -Force
    }
    if (Test-Path -LiteralPath $dir) {
        if (-not $vm -and -not (Test-Path -LiteralPath (Join-Path $dir '.lab-kit-disposable'))) {
            throw "$dir has no VM and no .lab-kit-disposable marker; not removing it"
        }
        Remove-Item -LiteralPath $dir -Recurse -Force
    }
    "removed $n"
}
