## berries

berries is my k8s on raspberri "cluster".

## How to bootstrap

Assuming you are in the `berries` root folder:

### Flux

#### Install Flux Operator and FluxInstance

```bash
set -e
for chart in flux-operator flux-instance; do
  app="./apps/flux-system/$chart/app"
  helm upgrade --install "$chart" "$(yq -r '.spec.url' "$app/ocirepository.yaml")" \
    --kube-context admin@berries --namespace flux-system --create-namespace \
    --version "$(yq -r '.spec.ref.tag' "$app/ocirepository.yaml")" \
    --values <(yq '.spec.values' "$app/helmrelease.yaml") --wait --timeout 5m
done
kubectl --context admin@berries -n flux-system wait --for=condition=Ready \
  fluxinstance/flux --timeout=5m
```

### Apply Cluster Configuration

_These cannot be applied with `kubectl` in the regular fashion due to some files being encrypted with sops_

```sh
sops --decrypt ./bootstrap/age-key.sops.yaml | kubectl --context admin@berries apply -f -
kubectl --context admin@berries apply -f ./flux/vars/cluster-settings.yaml
```

### Kick off Flux applying this repository

```sh
kubectl --context admin@berries apply --server-side --kustomize ./flux/config
```
