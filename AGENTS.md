# Agent Guide

This is the vendor-neutral brief for coding agents working in `lab-kit`.

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

## Checks

```bash
bash -n bin/run-scenario.sh scenarios/common/*.sh
```
