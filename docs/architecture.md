# Architecture

Lab Kit separates three concerns:

1. The appliance under test.
2. The lab infrastructure needed to test it.
3. The hypervisor used to run that infrastructure.

The appliance repo should own appliance-specific scripts and scenarios. Lab Kit
should own reusable orchestration patterns. Router images, Windows images, and
other reusable fixtures should live in their own projects when they become
useful outside one appliance.

## Dependency Direction

The intended dependency direction is:

```text
appliance repo
  uses
lab-kit
  provisions or consumes
fixture appliances such as lab-router
```

Fixture appliances should not depend on a specific appliance repo. Lab Kit
should not depend on a specific appliance repo. Appliance repos can provide
topology files and scenarios that use both.

## Hypervisor Boundary

Portable labs need a small vocabulary of backend operations:

- create network
- create VM
- attach NIC
- set VLAN or trunk mode
- mount ISO
- start/stop VM
- snapshot VM
- revert snapshot
- copy file to guest
- run command in guest or through SSH

The first implementation keeps these as scripts and environment conventions.
Later, this can become a stricter backend interface.

## Scenario Boundary

Scenarios should assert final state, not only command success. For appliance
labs, useful assertions usually include:

- service state
- network reachability
- DNS behavior
- authentication behavior
- replication or clustering health
- logs from the peer system, not only local output

Keep scenario files project-specific when they know domain details. Move common
checks into `scenarios/common/` only after two projects need them.
