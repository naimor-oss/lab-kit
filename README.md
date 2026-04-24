# Lab Kit

Lab Kit is a small orchestration toolkit for appliance build/test labs. It is
meant to make the boring lab work repeatable:

- define a topology
- create or reset VMs
- push current appliance scripts
- run scenarios
- collect logs

The first backend is Hyper-V because that is where the Samba AD DC appliance
lab started. The design keeps hypervisor-specific operations behind small
scripts so libvirt/QEMU, VMware, or other backends can be added later.

## Repository Map

| Path | Purpose |
| --- | --- |
| `bin/run-scenario.sh` | Generic scenario runner. |
| `hypervisors/hyperv/` | Hyper-V helper scripts. |
| `scenarios/common/` | Reusable scenario fragments and smoke checks. |
| `examples/` | Example topology and environment files. |
| `docs/` | Architecture and hypervisor notes. |

## Core Concepts

A lab has:

- one or more persistent fixtures, such as routers or seed domain controllers
- one or more appliances under test
- a scenario directory
- a result directory
- a hypervisor backend

A scenario is a shell file that defines:

```bash
run_scenario() { ...; }
verify() { ...; }
```

Optional hooks:

```bash
pre_hook() { ...; }
post_hook() { ...; }
```

## Quick Start

Copy an example environment file and edit it for your lab:

```bash
cp examples/samba-addc.env .env
```

Then run a scenario:

```bash
LAB_ENV=.env bin/run-scenario.sh scenarios/my-scenario.sh
```

The runner provides helpers to scenario files:

- `ssh_host`
- `ssh_vm`
- `scp_to_vm`
- `say`
- `step`

The helper names are intentionally simple. Backend-specific complexity belongs
in backend scripts, not in every scenario.

## Status

This is the initial extraction from the Samba AD DC appliance lab. It is usable
as a starting point, but the topology model is intentionally still light. The
next step is to add a neutral YAML topology file and map it into backend
operations such as create network, create VM, attach NIC, snapshot, revert,
guest exec, and copy to guest.
