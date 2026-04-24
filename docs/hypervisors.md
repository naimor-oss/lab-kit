# Hypervisors

Lab Kit starts with Hyper-V but should stay portable.

## Hyper-V

The Hyper-V backend assumes:

- PowerShell is available over SSH on the host.
- VM helper scripts are staged onto a host-visible share.
- Appliance VMs are reachable by SSH after boot.

Current helper:

- `hypervisors/hyperv/Revert-TestVM.ps1`

Project-specific repos can bring additional Hyper-V scripts until common
patterns settle.

## Future Backends

Likely next backends:

- libvirt/QEMU using `virsh`, cloud-init, and qcow2 disks
- VMware using PowerCLI or `vmrun`

Do not force every backend to expose identical internals. Keep the scenario
surface stable and map backend differences underneath.
