# Agent Guide

This is the vendor-neutral brief for coding agents working in `lab-kit`.

**General conventions, project narrative, and shared decisions live in
the sibling repo [`../dev-commons/`](../dev-commons/).** Read at least
[`../dev-commons/CONTEXT.md`](../dev-commons/CONTEXT.md) and
[`../dev-commons/STYLE.md`](../dev-commons/STYLE.md) before substantive
work here. This file covers what's specific to `lab-kit`.

## Project Purpose

`lab-kit` is reusable orchestration for appliance build/test labs. It should
provide scenario running, hypervisor backend helpers, topology conventions, and
log collection without depending on any one appliance.

## Boundaries

- Keep appliance-specific behavior out of this repo.
- Keep router image internals out of this repo; use `lab-router` as a fixture
  or dependency when needed.
- Hyper-V is the first backend, but new code should leave room for libvirt,
  VMware, or other backends.
- Scenario helpers should be generic only after more than one appliance needs
  them.

## Development Rules

- Prefer simple shell and small backend scripts.
- Keep backend-specific assumptions under `hypervisors/<backend>/`.
- Put reusable docs in `docs/`.
- Keep private agent folders such as `.claude/`, `.codex/`, `.cursor/`,
  `.continue/`, and `.aider*` untracked.

## Workstation portability

`lib/lab-host.sh` is the only place that knows about the operator's
workstation: WSL2 on Windows 11 (supported), macOS (legacy) or plain Linux.
It provides the ISO share path (`lab_iso_dir`), the NoCloud seed ISO
builder (`lab_make_seed_iso`, label `CIDATA`), checksums and install hints.
Appliance lab scripts and `lab-router` source it from the sibling checkout;
never call `hdiutil`, `shasum` or `/Volumes/...` directly in a lab script.
Setup: `../dev-commons/WSL2-LAB-SETUP.md`.

## Checks

```bash
bash -n bin/run-scenario.sh lib/*.sh scenarios/common/*.sh
bash tests/lab-host.sh
bash tests/smoke-runner.sh
```
