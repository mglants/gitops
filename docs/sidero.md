# Sidero

The following applies to sidero v0.5
## Dependencies

- kubectl
    ```
    sudo pacman -S kubectl
    ```
- clusterctl 0.4.5
    ```
    curl -Lo /usr/local/bin/clusterctl \
    "https://github.com/kubernetes-sigs/cluster-api/releases/download/v0.4.5/clusterctl-linux-amd64"
    chmod +x /usr/local/bin/clusterctl
    ```
- talosctl 0.14.0
     ```
    sudo curl -Lo /usr/local/bin/talosctl \
    "https://github.com/talos-systems/talos/releases/latest/download/talosctl-linux-amd64"
    chmod +x /usr/local/bin/talosctl
     ```

## Install Talos

### UR30
vmware.sh from custom/vsphere/sidero
### SweetHome RPI4

Flash USB SSD with Talos image, (found here.)[https://github.com/talos-systems/talos/releases/latest/download/metal-rpi_4-arm64.img.xz]


## Creating management cluster
### UR30
```bash
#ip of single-node cluster running talos
export SIDERO_ENDPOINT=192.168.48.200

#generate config
cd custom/vsphere/sidero
talosctl gen config --config-patch-control-plane @cp.patch.yaml ur30-sidero "https://${SIDERO_ENDPOINT}:6443/"
```

### SweetHome
```bash
#ip of single-node cluster running talos
export SIDERO_ENDPOINT=172.16.30.200

#generate config
talosctl gen config --config-patch='[{"op": "add", "path": "/cluster/allowSchedulingOnMasters", "value": true},{"op": "replace", "path": "/machine/install/disk", "value": "/dev/sda"}]' sh-sidero "https://${SIDERO_ENDPOINT}:6443/"
```
```bash
#apply generated config
talosctl apply-config --insecure -n ${SIDERO_ENDPOINT} -f controlplane.yaml

#merge client config into ~/.talos/config
talosctl config merge talosconfig

#update config endpoints/nodes
talosctl config endpoints ${SIDERO_ENDPOINT}
talosctl config nodes ${SIDERO_ENDPOINT}

#bootstrap etcd
talosctl bootstrap

#fetch kubeconfig
talosctl kubeconfig

#wait for log "[talos] bootstrap sequence: done" before continuing
talosctl dmesg -f | grep "bootstrap sequence: done"

# seems to take a couple minutes after that log before 6443 is open and it's ready for the clusterctl command

#init management cluster
SIDERO_CONTROLLER_MANAGER_HOST_NETWORK=true \
SIDERO_CONTROLLER_MANAGER_DEPLOYMENT_STRATEGY=Recreate \
SIDERO_CONTROLLER_MANAGER_API_ENDPOINT=${SIDERO_ENDPOINT} \
SIDERO_CONTROLLER_MANAGER_SIDEROLINK_ENDPOINT=${SIDERO_ENDPOINT} \
clusterctl init -i sidero -b talos -c talos

#verify admin cluster
curl -I "http://${SIDERO_ENDPOINT}:8081/tftp/ipxe.efi"
```

## Setting up DHCP

```bash
# example ipxe-metal.conf located in /sidero/dhcp
set service dhcp-server global-parameters 'option system-arch code 93 = unsigned integer 16;'
set service dhcp-server shared-network-name VLAN10 subnet 192.168.1.0/24 subnet-parameters "include &quot;/config/ipxe-metal.conf&quot;;"
```

## Configure servers
(follow guide to configure rpi4 as servers with PXE boot)[https://www.sidero.dev/docs/v0.5/guides/rpi4-as-servers/#build-the-image-with-the-boot-folder-contents]

### SweetHome Patch metal controller
__TODO: move this into a kustomization__
(As per the documentation here)[https://www.sidero.dev/docs/v0.5/guides/rpi4-as-servers/#patch-metal-controller], we need to patch the sidero-controller-manager so the RPI4's can boot over network boot = UEFI.

```bash
kubectl -n sidero-system patch deployments.apps sidero-controller-manager --patch "$(cat ./manifests/management/core/sidero/patches/controller.patch.yaml)"
```
### UR30 Patch secret
```bash
talosctl -n ${SIDERO_ENDPOINT} config new vmtoolsd-secret.yaml --roles os:admin

kubectl -n kube-system create secret generic talos-vmtoolsd-config \
  --from-file=talosconfig=./vmtoolsd-secret.yaml

rm vmtoolsd-secret.yaml
```
## Bootstrap Flux
Ensure we're using the correct context
### UR30
```bash
kubectx admin@ur30-sidero
```
### SweetHome
```bash
kubectx admin@sh-sidero
```

Run pre-installation checks
```bash
flux check --pre
```
Create flux-system namespace
```bash
kubectl create namespace flux-system
```
Add Age key for SOPS
```bash
cat flux.agekey | kubectl create secret generic sops-age \
    --namespace=flux-system \
    --from-file=age.agekey=/dev/stdin
```
Install Flux
### UR30
```bash
# due to a race condition with the Flux CRDs, this command will need to be run twice
kubectl apply --kustomize=./manifests/ur30/sidero/gitops/flux-system
```
### SweetHome
```bash
# due to a race condition with the Flux CRDs, this command will need to be run twice
kubectl apply --kustomize=./manifests/sh/sidero/gitops/flux-system
```

## Get kubeconfig

### UR30
```bash
# fetch kubeconfig
kubectl get secret -n flux-system vmware-kubeconfig -o yaml -o jsonpath='{.data.value}' | base64 -d > kubeconfig
```

### SweetHome

```bash
# fetch kubeconfig
kubectl get secret -n flux-system berries-kubeconfig -o yaml -o jsonpath='{.data.value}' | base64 -d > kubeconfig
```

```bash
# merge kubeconfig files
cp ~/.kube/config ~/.kube/config.bak
KUBECONFIG=~/.kube/config:$(pwd)/kubeconfig kubectl config view --flatten > /tmp/kubeconfig
mv /tmp/kubeconfig ~/.kube/config
```

## Tidy up context names

```bash
kubectx sh-sidero=admin@sh-sidero
kubectx sh-berries=berries-admin@berries
kubectx ur30-sidero=admin@ur30-sidero
kubectx ur30-vmware=vmware-admin@vmware
```

## Updating
Upgrade managment plane(sidero)
```bash
clusterctl upgrade plan
```
