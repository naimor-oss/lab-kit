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

## Where do I start?

| If you want to … | Read |
| --- | --- |
| Understand the **runner pipeline and scenario contract** | [`docs/architecture.md`](docs/architecture.md) |
| Add a **new hypervisor backend** | [`docs/hypervisors.md`](docs/hypervisors.md) |
| Wire **a new appliance** into the runner | [`examples/samba-addc.env`](examples/samba-addc.env) as the reference env file |
| Look up **shared coding/docs conventions** | [`../dev-commons/STYLE.md`](../dev-commons/STYLE.md) |
| Understand the **sibling-repo split** | [`../dev-commons/REPO-SPLIT.md`](../dev-commons/REPO-SPLIT.md) |

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

## Pipeline

Each run walks this pipeline; any step is skippable via a flag.

| Step | Driven by | Flag to skip |
| --- | --- | --- |
| stage | `LAB_STAGE_SOURCES` globs copied to `LAB_STAGE_DIR` | `--no-stage` |
| reset | `Revert-TestVM.ps1` via `LAB_STAGE_DIR` | `--no-reset` |
| push | `scp LAB_PUSH_FILES` to `LAB_REMOTE_PUSH_DIR` | `--no-push` |
| post-push | `LAB_POST_PUSH_CMD` on the VM | `--no-push` |
| `pre_hook` | scenario | — |
| `run_scenario` | scenario | — |
| `verify` | scenario | — |
| `post_hook` | scenario | — |

`--verify-only` implies all `--no-*` and skips the scenario body plus the
pre/post hooks.

## Status

One real consumer today: the [`samba-addc-appliance`](https://github.com/naimor-oss/samba-addc-appliance)
repo uses this runner end to end (stage, revert, push, post-push command,
scenario pre/run/verify/post hooks, log capture). The pipeline surface is
stable; no breaking changes planned before a second appliance arrives.

One hypervisor backend today (Hyper-V over SSH). Adding libvirt or VMware
is mostly a matter of replacing the revert helper and the command that
the runner invokes on the host; the scenario surface should not need to
change.

Intentionally not shipped yet:

- A neutral YAML topology file. It is tempting to design one now, but
  lab-kit has one consumer - the topology would end up describing the
  Samba lab. Waiting for a second consumer before generalizing.
- A guest-exec abstraction. `ssh_vm` is enough for current scenarios.
- A snapshot-create helper. Test cycles work off a pre-existing
  `golden-image` checkpoint; scenarios only need revert.
