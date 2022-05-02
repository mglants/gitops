#!/bin/bash

set -e

## The following commented environment variables should be set
## before running this script

# export GOVC_USERNAME='administrator@vsphere.local'
# export GOVC_INSECURE=true
# export GOVC_URL='https://vsphere.ur30.ru'
# export GOVC_DATACENTER='UR30'
# export GOVC_PASSWORD='xxx'

CLUSTER_NAME=${CLUSTER_NAME:=vmware}

CONTROL_PLANE_POOL=${CONTROL_PLANE_POOL:=sidero}
CONTROL_PLANE_COUNT=${CONTROL_PLANE_COUNT:=2}
CONTROL_PLANE_CPU=${CONTROL_PLANE_CPU:=4}
CONTROL_PLANE_MEM=${CONTROL_PLANE_MEM:=4096}
CONTROL_PLANE_DISK=${CONTROL_PLANE_DISK:=30G}
CONTROL_PLANE_NETWORK=${CONTROL_PLANE_NETWORK:=UR30_K8s48}
CONTROL_PLANE_DATASTORE=${CONTROL_PLANE_DATASTORE:=Fasty}

WORKER_POOL=${WORKER_PLANE_POOL:=sidero}
WORKER_COUNT=${WORKER_COUNT:=0}
WORKER_CPU=${WORKER_CPU:=8}
WORKER_MEM=${WORKER_MEM:=12288}
WORKER_DISK=${WORKER_DISK:=100G}
WORKER_NETWORK=${WORKER_NETWORK:=UR30_K8s48}
WORKER_DATASTORE=${WORKER_PLANE_DATASTORE:=Fasty}

create () {

    ## Create control plane nodes and edit their settings

    for i in $(seq 1 ${CONTROL_PLANE_COUNT}); do
        echo ""
        echo "launching control plane node: ${CLUSTER_NAME}-control-plane-${i}"
        echo ""
        existance=$(govc vm.info ${CLUSTER_NAME}-control-plane-${i}| wc -w )
        if [ $existance -eq 0 ]; then
            govc vm.create \
            -c=${CONTROL_PLANE_CPU} \
            -m=${CONTROL_PLANE_MEM} \
            -g=other3xLinux64Guest \
            -net=${CONTROL_PLANE_NETWORK} \
            -disk.controller=pvscsi \
            -disk=${CONTROL_PLANE_DISK} \
            -disk-datastore=${CONTROL_PLANE_DATASTORE} \
            -pool=${CONTROL_PLANE_POOL} \
            -on=false \
            ${CLUSTER_NAME}-control-plane-${i}

            govc vm.change \
            -e "disk.enableUUID=1" \
            -vm ${CLUSTER_NAME}-control-plane-${i}

            # govc vm.power -on ${CLUSTER_NAME}-control-plane-${i}
        else
            echo "Node ${CLUSTER_NAME}-control-plane-${i} already exists"
        fi
    done

    # Create worker nodes and edit their settings
    for i in $(seq 1 ${WORKER_COUNT}); do
        echo ""
        echo "launching worker node: ${CLUSTER_NAME}-worker-${i}"
        echo ""
        existance=$(govc vm.info ${CLUSTER_NAME}-worker-${i}| wc -w )
        if [ $existance -eq 0 ]; then
            govc vm.create \
            -c=${WORKER_CPU} \
            -m=${WORKER_MEM} \
            -g=other3xLinux64Guest \
            -net=${WORKER_NETWORK} \
            -disk=${WORKER_DISK} \
            -disk.controller=pvscsi \
            -disk-datastore=${WORKER_DATASTORE} \
            -pool=${WORKER_POOL} \
            -on=false \
            ${CLUSTER_NAME}-worker-${i}

            govc vm.change \
            -e "disk.enableUUID=1" \
            -vm ${CLUSTER_NAME}-worker-${i}

            # govc vm.power -on ${CLUSTER_NAME}-worker-${i}
        else
            echo "Node ${CLUSTER_NAME}-worker-${i} already exists"
        fi
    done

}

destroy() {
    for i in $(seq 1 ${CONTROL_PLANE_COUNT}); do
        echo ""
        echo "destroying control plane node: ${CLUSTER_NAME}-control-plane-${i}"
        echo ""

        govc vm.destroy ${CLUSTER_NAME}-control-plane-${i}
    done

    for i in $(seq 1 ${WORKER_COUNT}); do
        echo ""
        echo "destroying worker node: ${CLUSTER_NAME}-worker-${i}"
        echo ""
        govc vm.destroy ${CLUSTER_NAME}-worker-${i}
    done
}

"$@"
