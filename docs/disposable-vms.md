# Disposable test VMs and sealed base disks

How to make a test VM in seconds, throw it away after use, and keep the
disk it starts from current. Hyper-V today; `bin/lab-vm` drives it from WSL2
on the Hyper-V host or over SSH.

## Where do I start?

| If you want to … | Do |
| --- | --- |
| Get a VM to test on | `lab-vm new t1` (prints its IP), `lab-vm ssh t1` |
| Throw it away | `lab-vm rm t1` |
| Make or refresh a base disk | `lab-vm build-base -s SRC.vhdx -o BASE-YYYYMMDD.vhdx --upgrade` |
| Run a VM someone built elsewhere, from its files | `lab-vm register DIR --start` |
| Configure it for your lab | the variables at the top of `bin/lab-vm` |

## The model

```text
cloud image (.vhdx)  ──build-base──►  sealed base, dated, read-only
                     (seed, upgrade,      │
                      prep, seal)         ├──new──►  t1   (own disk, own seed)
                                          ├──new──►  t2
                                          └──new──►  …    rm when done
```

- **Bases are files, not checkpoints.** A base is a standalone VHDX,
  written once, read-only, with the date in its name. Refreshing it means
  building a new one, not upgrading one in place. A build always starts from
  the cloud image, so it can't pick up leftovers from earlier test runs, and
  the previous base stays usable until nothing needs it.
- **Bases are sealed.** `seal` removes what makes a machine unique:
  `machine-id`, SSH host keys and cloud-init's state. The base is then
  powered off and never booted again. Without this, every VM made from it
  would get the same DHCP lease (systemd-networkd derives the client ID from
  `machine-id`) and the same host keys.
- **Each VM gets its identity from its own seed.** `new` writes a NoCloud
  seed ISO with the VM's hostname, the lab user and key, and DHCP on any
  Ethernet interface. cloud-init applies it on first boot.
- **VMs are cattle.** Every VM `new` makes is tagged `lab-kit:disposable` in
  its Notes. `rm` refuses any VM without that tag, and deletes only that
  VM's own folder, never a base.

## Disk copies: block clone or differencing disk

`New-TestVM.ps1 -DiskMode Auto` (the default) picks per VM folder:

| VM folder on | Mode | Cost |
| --- | --- | --- |
| ReFS (e.g. a Windows Dev Drive) | full copy, which ReFS makes as a block clone | well under a second, and no space used until the VM writes |
| anything else | differencing disk with the base as parent | also instant, but the base must never move or change |

On ReFS, a copy is as fast as a differencing disk and the VM doesn't depend
on its base: you can delete an old base while VMs made from it still run.
Measured on a Dev Drive: 0.09 s to copy a 1.2 GB VHDX on the Windows side.
The same copy from WSL2 (through `/mnt/d`) takes 20 s, which is why disks are
always copied on the host.

## Measured (Windows 11 client Hyper-V, Dev Drive, 2026-10-15)

| Step | Time |
| --- | --- |
| `fetch-debian` (download, SHA512, convert) | 51 s |
| `build-base --upgrade` (build VM to published sealed base) | about 35 s |
| `new`, two VMs started in parallel, until both answer SSH | 24 s |
| `register` an exported VM folder, until it answers SSH | 12 s |

## Rights: no elevation needed

The scripts in `hypervisors/hyperv/` need Hyper-V rights, not
administrator rights. A Windows user in the local **Hyper-V Administrators**
group can run them from a non-elevated shell, so `lab-vm` works from WSL2
with no UAC prompt. Membership counts from that user's next sign-in. It is
close to admin-equivalent on that host: whoever controls Hyper-V can attach
any disk to a VM. Creating switches, NAT and host vNIC addresses still needs
elevation (`lab-router`).

## IP addresses

`lab-vm` finds a VM's IP one of two ways:

- `LAB_ROUTER_SSH=user@router`: reads the lab router's dnsmasq lease file
  and matches the VM's MAC. Works from first boot, with no guest agent.
- Otherwise: the address Hyper-V reports through KVP, which needs
  `hyperv-daemons` in the guest. Give the base that package
  (`--packages hyperv-daemons`).

## Building a base

```sh
lab-vm build-base -s 'D:\Lab\ISO\debian-13-genericcloud.vhdx' \
    -o 'D:\Lab\bases\debian-13-blank-20261015.vhdx' \
    --upgrade --packages "hyperv-daemons curl"
```

It creates a build VM from the source disk, waits for cloud-init (full
upgrade and packages), runs `--prep CMD` on it if given (e.g. an appliance's
image preparation), seals it, publishes the disk and removes the build VM.
Each step prints how long it took.

## Registering in place

`lab-vm register DIR` runs `Import-VM -Register` on a VM folder that is
already where it should stay, for example an exported appliance build copied
to the lab share. No copy, same VM ID. It registers one VM. To get several
VMs from one build, publish its disk as a base and use `new`.

Without elevation, registering needs the files to belong to the user who
registers them: Hyper-V sets each disk's ACL for the VM, and only an owner
may do that. Files that `Export-VM` wrote belong to `SYSTEM`, so
`Register-TestVM.ps1` first replaces any file the user doesn't own with the
user's own copy (a block clone on ReFS, a real copy elsewhere). ISO files
aren't part of an export; a DVD drive whose media is missing is ejected,
with a warning.
