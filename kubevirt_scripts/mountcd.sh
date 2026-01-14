#!/bin/bash
set -ux -o pipefail

#### IMPORTANT: This script is only meant to show how to implement required scripts to make custom hardware compatible with FakeFish.
#### This script has to mount the iso in the server's virtualmedia and return 0 if operation succeeded, 1 otherwise
#### Note: Iso image to mount will be received as the first argument ($1)
#### You will get the following vars as environment vars
#### BMC_ENDPOINT - Has the BMC IP
#### BMC_USERNAME - Has the username configured in the BMH/InstallConfig and that is used to access BMC_ENDPOINT
#### BMC_PASSWORD - Has the password configured in the BMH/InstallConfig and that is used to access BMC_ENDPOINT

ISO=${1}
IS_HTTPS=false

export VM_NAME=$(echo $BMC_ENDPOINT | awk -F "_" '{print $1}')
export VM_NAMESPACE=$(echo $BMC_ENDPOINT | awk -F "_" '{print $2}')

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

source ${SCRIPTPATH}/common.sh

if [[ -r /var/tmp/kubeconfig ]]; then
  export KUBECONFIG=/var/tmp/kubeconfig
fi


CLUSTER_STORAGE_CLASS=$(oc get storageclass | awk '/(default)/ {print $1}')
if [ $? -ne 0 ]; then
  echo "Failed to get default cluster's storage class."
  exit 1
fi

# we need to poweroff the VM if it's running
VM_WAS_RUNNING=$(oc -n ${VM_NAMESPACE} get vm ${VM_NAME} -o jsonpath='{.spec.running}')
if [ $? -ne 0 ]; then
  echo "Failed to get VM power state."
  exit 1
fi
stop_vm
if [ $? -ne 0 ]; then
  echo "Failed to poweroff VM."
  exit 1
fi

# Download ISO and use virtctl to upload it to a PVC
WAIT=60
ISO_FILENAME=$(basename "${ISO}")

if [[ ! -r /tmp/${ISO_FILENAME} ]]; then
  curl \
    --insecure \
    --location \
    --silent \
    --output-dir /tmp  \
    --remote-name \
    --retry 3 \
    --retry-max-time ${WAIT} \
    "${ISO}" || {
      echo "Failed to download ISO: ${ISO}"
      exit 1
    }
fi

if ! oc -n ${VM_NAMESPACE} get pvc ${VM_NAME}-bootiso &> /dev/null; then
  timeout ${WAIT} \
    virtctl \
      -n ${VM_NAMESPACE} \
      image-upload \
      pvc \
      ${VM_NAME}-bootiso \
      --image-path=/tmp/${ISO_FILENAME} \
      --insecure \
      --size 5Gi || {
        echo "Failed to upload ISO to PVC: ${VM_NAME}-bootiso with ISO: /tmp/${ISO_FILENAME}"
        exit 1
      }

  rm -f /tmp/${ISO_FILENAME}
fi

NUM_VOLUMES=$(oc -n ${VM_NAMESPACE} get vm ${VM_NAME} -o jsonpath='{.spec.template.spec.volumes[*].name}' | tr " " ";" | { grep -o ";" || true; } | wc -l)
if [ $? -ne 0 ]; then
  echo "Failed to get VM volumes."
  exit 1
fi

cat <<EOF > /tmp/${VM_NAME}.patch
[
  {
    "op": "add",
    "path": "/spec/template/spec/volumes/$((NUM_VOLUMES + 1))",
    "value": {
      "name": "${VM_NAME}-bootiso",
      "persistentVolumeClaim": {
         "claimName": "${VM_NAME}-bootiso"
      }
    }
  }
]
EOF

# Add it to VM object if it doesn't exist
VOLUME_EXIST=$(oc -n ${VM_NAMESPACE} get vm ${VM_NAME} -o jsonpath='{.spec.template.spec.volumes[*].name}' | { grep -c "${VM_NAME}-bootiso" || true; })
if [ $? -ne 0 ]; then
  echo "Failed to get VM volumes."
  exit 1
fi

if [ ${VOLUME_EXIST} -eq 0 ]; then
  oc -n ${VM_NAMESPACE} patch vm ${VM_NAME} --patch-file /tmp/${VM_NAME}.patch --type json
  if [ $? -eq 0 ]; then
    echo "Volume added to the VM"
  else
    echo "Failed to add bootiso volume to the VM"
    exit 1
  fi
else
  echo "Volume already added to the VM"
fi

# We get the number of disks, since we need to delete the one we just added to fix the config
NUM_DISK=$(oc -n ${VM_NAMESPACE} get vm ${VM_NAME} -o jsonpath='{.spec.template.spec.domain.devices.disks[*].name}' | tr " " ";" | { grep -o ";" || true; } | wc -l)
if [ $? -ne 0 ]; then
  echo "Failed to get VM disks."
  exit 1
fi

cat <<EOF > /tmp/${VM_NAME}.patch
[
  {
    "op": "add",
    "path": "/spec/template/spec/domain/devices/disks/$((NUM_DISK + 1))",
    "value": {
      "bootOrder": $((NUM_DISK + 2)),
      "cdrom": {
         "bus": "sata"
      },
      "name": "${VM_NAME}-bootiso"
    }
  }
]
EOF

# Add it to VM object if it doesn't exist
DISK_EXIST=$(oc -n ${VM_NAMESPACE} get vm ${VM_NAME} -o jsonpath='{.spec.template.spec.domain.devices.disks[*].name}' | { grep -c "${VM_NAME}-bootiso" || true; })
if [ $? -ne 0 ]; then
  echo "Failed to get VM volumes."
  exit 1
fi

if [ ${DISK_EXIST} -eq 0 ]; then
  oc -n ${VM_NAMESPACE} patch vm ${VM_NAME} --patch-file /tmp/${VM_NAME}.patch --type json
  if [ $? -eq 0 ]; then
    echo "Disk added to the VM"
  else
    echo "Failed to add bootiso disk to the VM"
    exit 1
  fi
else
  echo "Volume already added to the VM"
fi

# If VM was running, restore it
if [[ "${VM_WAS_RUNNING}" == "true" ]]; then
  start_vm
  if [ $? -ne 0 ]; then
    echo "Failed to poweron VM."
    exit 1
  fi
fi
