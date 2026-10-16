# Hypervisors

Lab Kit starts with Hyper-V but should stay portable.

## Hyper-V

The Hyper-V backend assumes:

- PowerShell is available over SSH on the host.
- VM helper scripts are staged onto a host-visible share.
- Appliance VMs are reachable by SSH after boot.

Helpers (each needs Hyper-V rights only, not elevation; see
[`disposable-vms.md`](disposable-vms.md), "Rights"):

| Script | Does |
| --- | --- |
| `Revert-TestVM.ps1` | Restore a checkpoint and start (scenario runner) |
| `New-TestVM.ps1` | VM from a sealed base: block-clone copy on ReFS, else differencing disk |
| `Remove-TestVM.ps1` | Delete a VM tagged `lab-kit:disposable`, and only its folder |
| `Publish-BaseVhdx.ps1` | Powered-off VM's disk to a standalone, read-only base VHDX |
| `Register-TestVM.ps1` | `Import-VM -Register` a VM folder in place |
| `Get-TestVMInfo.ps1` | State, MAC and KVP IPv4 as `key=value` lines |

`bin/lab-vm` runs them locally through `powershell.exe` (WSL2 on the
Hyper-V host) or over SSH (`LAB_HYPERV=ssh:user@host`).

Project-specific repos can bring additional Hyper-V scripts until common
patterns settle.

## Future Backends

Likely next backends:

- libvirt/QEMU using `virsh`, cloud-init, and qcow2 disks
- VMware using PowerCLI or `vmrun`

Do not force every backend to expose identical internals. Keep the scenario
surface stable and map backend differences underneath.
