## subterra

subterra is my k8s undergound cluster for big resources

## How to bootstrap

Assuming you are in the `subterra` root folder:

### Flux

#### Install Flux Operator and FluxInstance

```bash
set -e
for chart in flux-operator flux-instance; do
  app="./apps/flux-system/$chart/app"
  helm upgrade --install "$chart" "$(yq -r '.spec.url' "$app/ocirepository.yaml")" \
    --kube-context admin@subterra --namespace flux-system --create-namespace \
    --version "$(yq -r '.spec.ref.tag' "$app/ocirepository.yaml")" \
    --values <(yq '.spec.values' "$app/helmrelease.yaml") --wait --timeout 5m
done
kubectl --context admin@subterra -n flux-system wait --for=condition=Ready \
  fluxinstance/flux --timeout=5m
```

### Apply Cluster Configuration

_These cannot be applied with `kubectl` in the regular fashion due to some files being encrypted with sops_

```sh
sops --decrypt ./bootstrap/age-key.sops.yaml | kubectl --context admin@subterra apply -f -
kubectl --context admin@subterra apply -f ./flux/vars/cluster-settings.yaml
```

### Kick off Flux applying this repository

```sh
kubectl --context admin@subterra apply --server-side --kustomize ./flux/config
```
