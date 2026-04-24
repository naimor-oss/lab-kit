# Common helper scenario: verify the appliance VM is reachable over SSH.

run_scenario() {
    ssh_vm 'hostname; uptime'
}

verify() {
    ssh_vm 'true'
}
