# Stop VM
# Always attempt to power off the VM, regardless of its current state.
# Capture the virtctl output that validates the state of the VM
# Retry until powered off or reach the max retries
function stop_vm() {
  MAX_RETRIES=5
  TRIES=1

  virtctl -n ${VM_NAMESPACE} stop ${VM_NAME}
  while true; do
    output=$(virtctl -n ${VM_NAMESPACE} stop ${VM_NAME} 2>&1 >/dev/null || true)
    if grep -q "VM is not running" <<< "${output}"; then
      return 0
    else
      if [[ ${TRIES} -ge ${MAX_RETRIES} ]]; then
        return 1
      fi
      TRIES=$(( ${TRIES} + 1 ))
      echo "Waiting to poweroff VM. Retrying in 5 seconds. Retry [${TRIES}/${MAX_RETRIES}]"
      sleep 5
    fi
  done
}

# Start VM
# Always attempt to power on the VM, regardless of its current state.
# Capture the virtctl output that validates the state of the VM
# Retry until ready or reach the max retries
function start_vm() {
  MAX_RETRIES=5
  TRIES=1

  virtctl -n ${VM_NAMESPACE} start ${VM_NAME} || true
  while true; do
    output=$(virtctl -n ${VM_NAMESPACE} start ${VM_NAME} 2>&1 >/dev/null || true)
    if grep -q "VM is already running" <<< "${output}"; then
      return 0
    else
      if [[ ${tries} -ge ${max_tries} ]]; then
        return 1
      fi
      tries=$(( ${tries} + 1 ))
      echo "Waiting to poweron VM. Retrying in 5 seconds. Retry [${TRIES}/${MAX_RETRIES}]"
      sleep 5
    fi
  done
}
