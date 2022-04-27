#!/bin/bash

set -e

## The following commented environment variables should be set 
## before running this script

# export GOVC_USERNAME='administrator@vsphere.local'
# export GOVC_INSECURE=true
# export GOVC_URL='https://vsphere.ur30.ru'
# export GOVC_RESOURCE_POOL='sidero'
# export GOVC_DATASTORE='Fasty'
# export GOVC_DATACENTER='UR30'
# export GOVC_NETWORK='UR30_K8s48'
# export GOVC_PASSWORD='xxx'

CLUSTER_NAME=${CLUSTER_NAME:=sidero}
TALOS_VERSION=${TALOS_VERSION:=v1.0.3}
OVA_PATH=${OVA_PATH:="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/vmware-amd64.ova"}

CONTROL_PLANE_COUNT=${CONTROL_PLANE_COUNT:=1}
CONTROL_PLANE_CPU=${CONTROL_PLANE_CPU:=0}
CONTROL_PLANE_MEM=${CONTROL_PLANE_MEM:=4096}
CONTROL_PLANE_DISK=${CONTROL_PLANE_DISK:=30G}
CONTROL_PLANE_MACHINE_CONFIG_PATH=${CONTROL_PLANE_MACHINE_CONFIG_PATH:="./controlplane.yaml"}

upload_ova () {
    ## Import desired Talos Linux OVA into a new content library
    govc library.create ${CLUSTER_NAME}
    govc library.import -n talos-${TALOS_VERSION} ${CLUSTER_NAME} ${OVA_PATH}
}

create () {
    ## Encode machine configs
    CONTROL_PLANE_B64_MACHINE_CONFIG=$(cat ${CONTROL_PLANE_MACHINE_CONFIG_PATH}| base64 | tr -d '\n')

    ## Create control plane nodes and edit their settings
    for i in $(seq 1 ${CONTROL_PLANE_COUNT}); do
        echo ""
        echo "launching control plane node: ${CLUSTER_NAME}-control-plane-${i}"
        echo ""

        govc library.deploy ${CLUSTER_NAME}/talos-${TALOS_VERSION} ${CLUSTER_NAME}-control-plane-${i}

        govc vm.change \
        -c ${CONTROL_PLANE_CPU}\
        -m ${CONTROL_PLANE_MEM} \
        -e "guestinfo.talos.config=${CONTROL_PLANE_B64_MACHINE_CONFIG}" \
        -e "disk.enableUUID=1" \
        -vm ${CLUSTER_NAME}-control-plane-${i}

        govc vm.disk.change -vm ${CLUSTER_NAME}-control-plane-${i} -disk.name disk-1000-0 -size ${CONTROL_PLANE_DISK}
        
        govc vm.power -on ${CLUSTER_NAME}-control-plane-${i}
    done

}

destroy() {
    for i in $(seq 1 ${CONTROL_PLANE_COUNT}); do
        echo ""
        echo "destroying control plane node: ${CLUSTER_NAME}-control-plane-${i}"
        echo ""

        govc vm.destroy ${CLUSTER_NAME}-control-plane-${i}
    done
}

delete_ova() {
    govc library.rm ${CLUSTER_NAME}
}

"$@"