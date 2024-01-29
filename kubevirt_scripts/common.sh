function stop_vm() {
  MAX_RETRIES=5
  TRIES=0
  VM_RUNNING=$(oc -n ${VM_NAMESPACE} get vm ${VM_NAME} -o jsonpath='{.spec.running}')
  if [ $? -ne 0 ]; then
    echo "Failed to get VM power state."
    return 1
  fi
  if [[ "${VM_RUNNING}" == "false" ]]; then
    echo "VM is already powered off"
  else
    while [[ ${VM_RUNNING} != "false" ]]
    do
      virtctl -n ${VM_NAMESPACE} stop ${VM_NAME}
      if [ $? -eq 0 ]; then
        return 0
      else
        if [[ ${TRIES} -ge ${MAX_RETRIES} ]];then
          echo "Failed to poweroff VM"
          return 1
        fi
        TRIES=$((TRIES + 1))
        echo "Failed to poweroff VM. Retrying in 5 seconds. Retry [${TRIES}/${MAX_RETRIES}]"
        sleep 5
      fi
    done
  fi
}

function start_vm() {
  MAX_RETRIES=5
  TRIES=0
  VM_RUNNING=$(oc -n ${VM_NAMESPACE} get vm ${VM_NAME} -o jsonpath='{.spec.running}')
  if [ $? -ne 0 ]; then
    echo "Failed to get VM power state."
    return 1
  fi
  if [[ "${VM_RUNNING}" == "true" ]]; then
    echo "VM is already running"
  else
    while [[ ${VM_RUNNING} != "true" ]]
    do
      virtctl -n ${VM_NAMESPACE} start ${VM_NAME}
      if [ $? -eq 0 ]; then
        return 0
      else
        if [[ ${TRIES} -ge ${MAX_RETRIES} ]];then
          echo "Failed to poweron VM"
          return 1
        fi
        TRIES=$((TRIES + 1))
        echo "Failed to poweron VM. Retrying in 5 seconds. Retry [${TRIES}/${MAX_RETRIES}]"
        sleep 5
      fi
    done
  fi
}