# Shared STUN/TURN

Coturn serves Fluxer/LiveKit, Jitsi/Prosody and Matrix/Synapse. Its persistent
authentication secret is `op://subterra/coturn/TURN_SHARED_SECRET`; ExternalSecrets
copy it into the existing `networking`, `apps` and `matrix` namespaces.

## Router forwarding

Keep UniFi's existing port 3478 forwarding. Add these rules, preserving ports:

| Public ports | Destination |
| --- | --- |
| TCP/UDP 3480 | 192.168.40.28, same ports |
| TCP 5349 | 192.168.40.28:5349 |
| UDP 49160–49259 | 192.168.40.28, same ports |
| TCP 443 | Existing Envoy VIP 192.168.40.2:443 |

The Cilium LoadBalancer exposes the entire relay range to the single coturn
instance. Coturn uses host networking on `subterra-cp2` and advertises
193.41.79.236 as its public relay address. NAT reflection is needed for LAN
clients and cluster peers using that address. If the WAN IP changes, update
coturn's `external-ip` and LiveKit's `rtc.node_ip`.

Local DNS maps `turn.glants.xyz` to 192.168.40.28. This Service also exposes TLS
on 443 by forwarding to coturn's 5349 listener. Public DNS aliases the hostname
to `ingress-ext.ur30.dev`. Public TCP 443 reaches coturn's plain TCP listener
through Envoy's TLS listener and the chart-generated TLSRoute.

## Migration

1. Deploy coturn and configure the router forwards before changing app settings.
2. Verify authenticated TURN allocation and media in both directions from outside
   the LAN, including the public relay range and TCP 443 path.
3. Reconcile the Envoy Gateway, shared TURN DNS and the app configurations together.
   The shared secret replaces Fluxer's derived secret and Synapse's static password.
   Jitsi receives temporary credential settings through `prosody.extraEnvs`.
4. Check Matrix P2P calls, Jitsi calls, and forced-relay Fluxer calls. Also check
   Fluxer's direct media paths for both LiveKit replicas.
5. Remove `matrix/stunner/ks.yaml` from the Matrix resource list after those checks;
   prune its configuration resources before uninstalling the operator. Check for
   remaining STUNner custom resources before deleting its CRDs.

STUNner is retained during preparation; it is not part of the coturn deployment.
The former Fluxer-specific coturn resources are removed by the Fluxer Helm upgrade.
App Flux Kustomizations depend on `cluster-apps-coturn`, so deploy the new networking
Kustomization before reconciling the application migrations.

## Capacity and availability

This starts with 100 relay ports and one coturn instance. Active allocations do
not survive a pod restart. Increase the relay range, Service ports and router
forwards together if usage requires it. Multiple replicas require separate relay
addresses/port ranges or routing that consistently selects the allocation owner.

STUN uses our port 3480 plus one Google endpoint as an additional candidate.
TURN authentication uses temporary credentials: 300 seconds for LiveKit and one
day for Synapse/Prosody. Credentials are issued by each application's server;
the shared signing secret is not sent to browser clients.
