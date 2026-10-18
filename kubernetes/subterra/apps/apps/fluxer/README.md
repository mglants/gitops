# Fluxer on Subterra

This Flux deployment uses bjw-s's `app-template` chart **5.0.1**, matching the
chart conventions used by other Subterra apps. One HelmRelease defines the
21 workloads, Services, probes and storage. Fluxer configuration is maintained
under `values.configMaps`, with container-specific variables grouped together in
`values.environment`. YAML aliases attach the relevant settings to each container;
shared variables are defined once. Secrets remain in ExternalSecret and the
Crunchy-generated PostgreSQL Secret. Public HTTP routing is under `values.route`
in the HelmRelease.

The deployment wiring was ported from Fluxer's official chart `0.1.0` at Git tag
`fluxer-api@2026.1015.210832` (commit
`3224f2113a2c386518602c9f5c8ee981267f7bb1`). That upstream GitRepository is no
longer required by Flux. The twelve Fluxer images retain the same verified
CalVer tags; API and worker share `fluxer-api:2026.1015.210832`.

The release uses the existing `apps` namespace. PostgreSQL 15 runs as a separate
Crunchy PostgresCluster (`fluxer-pgsql`) with three instances spread across the three nodes. Dragonfly runs as
`fluxer-dragonfly`, managed by the existing Dragonfly operator through the shared
repository component with a Fluxer-specific override: three replicas on distinct nodes, no password authentication
and no persistent storage. Each cache pod requests 256 MiB and retains its 768 MiB limit. PostgreSQL and Dragonfly are managed separately. The app-template release also includes
NATS, Meilisearch and LiveKit. NATS and JetStream run without authentication,
JetStream has three servers on distinct nodes, each with a retained 10 GiB PVC. Existing `JOBS` and `JOBS_DLQ` streams use three replicas.
Object storage uses the NAS S3 endpoint at
`https://nas.ur30.ru:30002`; bundled SeaweedFS is disabled.
It requests 100 GiB across seven `truenas-iscsi` volumes. Allow at least 8 GiB of
free cluster memory; resource limits are higher than requests.

## Traffic and DNS

`https://chat.glants.xyz` attaches to `networking/envoy-external`, listener
`https`, and uses the existing `*.glants.xyz` certificate. Envoy routes directly
to the application Services; Caddy is not deployed.

| Public path | Service | URL rewrite |
| --- | --- | --- |
| `/api` and descendants | `fluxer-api:8080` | Remove `/api` |
| `/gateway` and descendants | `fluxer-gateway:8080` | Remove `/gateway` |
| `/media` and descendants | `fluxer-media-proxy:8080` | Remove `/media` |
| `/livekit` and descendants | `fluxer-livekit:7880` | Remove `/livekit` |
| `/admin` and descendants | `fluxer-admin:8080` | Remove `/admin` |
| `/web`, `/emoji`, `/libs`, `/avatars`, `/badges`, `/desktop` and descendants | `fluxer-static-proxy:8080` | Preserve path |
| `/.well-known/fluxer`, `/_health` | `fluxer-api:8080` | Preserve path |
| All other paths | `fluxer-app-proxy:8080` | Preserve path |

HTTPRoute rules disable the request deadline; the route-scoped
BackendTrafficPolicy, generated through `values.rawResources`, permits one hour of stream inactivity. Uploads stream
without an added request-buffering policy. Reloader annotations
restart workloads when their referenced ConfigMaps or Secrets change.

The DNSEndpoint is consumed by the existing external-dns CRD sources. Its target,
`ingress-ext.ur30.dev`, resolves publicly to **193.41.79.236** and internally to
**192.168.40.2**. Forward TCP 80/443 to that Envoy VIP. The existing Envoy HTTP
listener redirects to HTTPS.

LiveKit media bypasses the HTTP gateway. Two LiveKit StatefulSet pods run on distinct nodes and share Dragonfly database 1 for room routing.
Each pod has its own media LoadBalancer Service with `externalTrafficPolicy: Local`: ordinal 0 uses **192.168.40.26**, TCP **7881** and UDP **7882**; ordinal 1 uses **192.168.40.27**, TCP **7883** and UDP **7884**. The VIP was unused in the live
Subterra Service allocations when prepared. Cilium's existing BGP configuration
advertises the VIP from nodes hosting the backend, so router rules do not depend
on the node running the pod.

Configure these router DNAT/firewall rules before testing external voice:

| Public destination | Internal destination |
| --- | --- |
| `193.41.79.236:7881/TCP` | `192.168.40.26:7881/TCP` |
| `193.41.79.236:7882/UDP` | `192.168.40.26:7882/UDP` |
| `193.41.79.236:7883/TCP` | `192.168.40.27:7883/TCP` |
| `193.41.79.236:7884/UDP` | `192.168.40.27:7884/UDP` |

Verify each media endpoint from outside the LAN before enabling both replicas.
A reachable signalling endpoint does not validate the media ports: an unreachable
secondary media endpoint causes intermittent call failures when rooms land there.
Include these ports in any required bypasses for router proxy or split-routing rules.

LiveKit explicitly advertises **193.41.79.236**, matching `dd.ur30.ru` and the
existing Subterra media configuration. STUN address discovery is disabled. If
the WAN address changes, update `rtc.node_ip` in `LIVEKIT_CONFIG`. LAN clients
using the public media address need router NAT reflection/hairpin support.
Router rules are not applied by these GitOps manifests.

Fluxer, Matrix and Jitsi share the coturn deployment in
`networking/coturn`. Restrictive client networks use TURN/TLS at
`turn.glants.xyz:443`, selected by a dedicated Envoy TLS listener. Envoy
terminates TLS and the shared coturn chart's TLSRoute forwards the connection
to its plain TCP listener on port 3480. The listener-specific ClientTrafficPolicy
disables HTTP ALPN for TURN traffic.

Coturn's LoadBalancer is **192.168.40.28**. Forward TCP/UDP **3480**, TCP
**5349**, and UDP **49160–49259** to that VIP without translating port numbers;
TCP **443** stays on Envoy **192.168.40.2**. UniFi retains port **3478**.
The relay range must be reachable publicly for Matrix P2P peers and through
NAT reflection for LAN clients. Coturn uses host networking on `subterra-cp2`
so its relay sockets have stable ports, and Cilium exposes all listener and
relay ports through the same VIP. Local DNS resolves `turn.glants.xyz` to the
coturn VIP, including a direct TLS listener on Service port 443. Public DNS
uses `ingress-ext.ur30.dev`.

The shared secret is persisted in `op://subterra/coturn/TURN_SHARED_SECRET`.
ExternalSecrets deliver it to coturn, Synapse, Prosody and Fluxer. LiveKit
issues temporary credentials valid for 300 seconds; Synapse and Prosody use
one day. Coturn requires authentication for relay allocations.

LiveKit v1.13.10 retains `rtc.advertise_internal_ip` so TURN can reach SFU pods
directly while clients retain public media candidates. Embedded LiveKit TURN
stays disabled. The former Fluxer-specific coturn workloads are removed when
the Fluxer migration is reconciled.

Client STUN uses `turn.glants.xyz:3480` with Google's STUN server retained as
an additional candidate. Fluxer's P2P voice STUN setting is configured separately.
TURN allocations are not migrated on restart; the single shared coturn instance
is a single point of failure and clients reconnect after interruptions.

The shared coturn deployment was checked on 2026-10-18 with STUN bindings,
unauthenticated allocation rejection, temporary credential authentication and
bidirectional UDP echo through UDP, TCP and TLS listeners. Router forwarding
and real application calls must be checked before retiring STUNner.

Validation on 2026-10-17 used isolated Chrome clients and synthetic audio in rooms
pinned to each LiveKit instance. Both direct connections and forced TURN/TLS
connections delivered audio. Selected ICE candidate statistics confirmed TLS
relaying; unauthenticated TURN allocation returned 401. A node reboot was not
part of this validation.

## First deployment

The four private buckets are provisioned on NAS HDD: `fluxer`, `fluxer-uploads`,
`fluxer-reports` and `fluxer-harvests`, using region `us-east-1`. A dedicated MinIO
access key named `fluxer` is restricted to these buckets by [s3/policy.json](s3/policy.json),
with bucket listing, object read/write/delete and multipart upload permissions.
Its credentials are stored in the `subterra/fluxer` 1Password item. Anonymous
access is disabled. The Kubernetes manifests do not provision this external storage.
Both cluster workloads and clients must reach `https://nas.ur30.ru:30002` with a valid
TLS certificate; this is also the endpoint advertised for direct uploads.
The NAS's existing CORS behavior allows upload preflights from
`https://chat.glants.xyz`. Its MinIO version does not implement per-bucket CORS;
no server-wide CORS settings were changed. Keep bucket access private; uploads
use signed URLs. If replacing the S3 service, allow that origin, methods `GET`,
`HEAD`, `PUT`, `POST`, and `DELETE`, request headers `*`, and expose `ETag`.

The durable source of Fluxer credentials is the `fluxer` item in 1Password,
accessed through `onepassword-connect`. External Secrets recreates `fluxer-env`
from that item, even after Fluxer and all its Kubernetes Secrets are deleted.
SMTP host, username and password come from the shared 1Password `smtp` item,
using its `SMTP_HOST`, `SMTP_USERNAME` and `SMTP_PASSWORD` fields. Email uses
implicit TLS on port 465, sender `noreply@glants.xyz` and display name `Fluxer`.
Workloads consume this Secret directly; the HelmRelease generates no credentials. Preserve the 1Password
item alongside the database, S3 buckets and persistent volume backups.

Create these fields in the item (or import the existing `fluxer-env` values if
recovering an already initialized installation):

```text
FLUXER_SEARCH_API_KEY
FLUXER_S3_ACCESS_KEY_ID
FLUXER_S3_SECRET_ACCESS_KEY
FLUXER_SUDO_MODE_SECRET
FLUXER_CONNECTION_INITIATION_SECRET
FLUXER_PROFILE_PSEUDONYM_SECRET
FLUXER_GATEWAY_RPC_AUTH_TOKEN
FLUXER_ERLANG_COOKIE
FLUXER_MEDIA_PROXY_SECRET_KEY
FLUXER_MEDIA_PROXY_UPLOAD_RELAY_SECRET_BASE64
FLUXER_ADMIN_SECRET_KEY_BASE
FLUXER_ADMIN_OAUTH_CLIENT_SECRET
FLUXER_SETUP_TOKEN
FLUXER_LIVEKIT_API_KEY
FLUXER_LIVEKIT_API_SECRET
FLUXER_VAPID_PUBLIC_KEY
FLUXER_VAPID_PRIVATE_KEY
```

For GIF search, add `FLUXER_KLIPY_API_KEY` to the same 1Password item. It defaults
to an empty value until configured; missing GIF credentials do not block secret synchronization.
For YouTube link previews, add `FLUXER_YOUTUBE_API_KEY` to that item. It is also
optional and defaults to an empty value until configured.

These fields include keys Fluxer's official chart could generate: storing them outside
Kubernetes ensures a complete redeployment does not generate replacements.
In particular, retain the profile pseudonym secret and matching VAPID key pair.
Other signing keys preserve token validation; retaining infrastructure passwords
also avoids changing credentials during recovery. Not every key is needed to
read stored data, but this configuration preserves all application credentials
without requiring a separate post-install secret export.

Use the NAS account's actual S3 credentials. For other random secrets, use a
distinct value of at least 32 characters, for example `openssl rand -hex 32`.
The LiveKit
API key may be `fluxer`. The upload relay secret must be standard base64 of at
least 32 random bytes (`openssl rand -base64 32`). VAPID requires a matching
P-256 key pair encoded as unpadded base64url (87 public / 43 private characters).
Store raw values in 1Password; External Secrets performs Kubernetes encoding.

The ExternalSecret lives alongside the HelmRelease in `app/`, following the
other Subterra applications. The Flux Kustomization depends on the existing
external-secrets stores. Missing item fields fail secret templating. Helm install
retries allow the first secret synchronization to complete before installation;
check ExternalSecret readiness if the HelmRelease is waiting for credentials.

Postgres credentials are generated by Crunchy in
`fluxer-pgsql-pguser-fluxer`. The API, worker, messages shard and users shard read
its `password` key directly, following the other applications' operator-secret
pattern. The Fluxer database role uses `options: SUPERUSER`, matching the other
Subterra application databases; no initialization SQL or bootstrap ConfigMap is needed.
No Postgres password is needed in the 1Password item. Connections use
`fluxer-pgsql-primary.apps.svc.cluster.local:5432`, database/user `fluxer`.
The workload environment uses `FLUXER_KV_URL=redis://fluxer-dragonfly:6379/0`.
The shared component configures a 768 MiB memory limit and no password or
snapshots. Dragonfly replicates its state to the other pods, but losing all replicas loses that state; PostgreSQL
and S3 remain the durable application stores.

Commit and push the manifests to the GitOps main branch, then let Flux reconcile,
or request reconciliation explicitly:

```sh
flux reconcile kustomization cluster-apps -n flux-system --with-source
flux reconcile kustomization cluster-apps-fluxer -n flux-system --with-source
kubectl -n apps get externalsecret fluxer
kubectl -n apps get helmrelease fluxer
kubectl -n apps get postgrescluster fluxer-pgsql
kubectl -n apps get dragonfly fluxer-dragonfly
kubectl -n apps get pods,pvc,httproute
kubectl -n apps get service fluxer-livekit-rtc
kubectl -n networking get gateway envoy-external
```

External Secrets refreshes `fluxer-env` from 1Password every hour. There are no
plaintext credentials in Git. Retrieve the initial setup token privately:

```sh
kubectl -n apps get secret fluxer-env -o jsonpath='{.data.FLUXER_SETUP_TOKEN}' | base64 -d
```

Open `https://chat.glants.xyz` and complete the owner setup. Username sign-in
works without SMTP. Email delivery is enabled through the shared SMTP service;
other integration credentials belong in a managed Secret rather than inline Helm values.

Verify the release and its public paths:

```sh
kubectl -n apps wait deployment -l app.kubernetes.io/instance=fluxer --for=condition=Available --timeout=15m
kubectl -n apps rollout status statefulset/fluxer-nats --timeout=15m
kubectl -n apps rollout status statefulset/fluxer-dragonfly --timeout=15m
kubectl -n apps rollout status statefulset/fluxer-meilisearch --timeout=15m
for path in /_health /api/_health /gateway/_health /media/_health /.well-known/fluxer /; do
  curl --fail --silent --show-error --output /dev/null "https://chat.glants.xyz${path}" || break
done
```

Also test a WebSocket session, attachment upload and voice call from the intended
client network. Confirm the HTTPRoute has `Accepted=True` and `ResolvedRefs=True`.

## Recovery and upgrades

Crunchy runs a full PostgreSQL backup on Sundays at 03:30 and differential
backups on the other days at 03:30. Backups use the existing `pgo-s3-creds`
Secret and NAS `crunchy-postgres` bucket, with repository path `/fluxer/repo1`
and 14-day retention. This is a new cluster; no restore dataSource is configured.
Backups of the four Fluxer S3 buckets and a secure backup of
`fluxer-env` must be arranged separately. Retain the other persistent volumes
for full recovery.
Do not delete PVCs or replace the secret to perform an upgrade.
Retain the `fluxer` 1Password item during full deletion/redeployment. Restore
application data before resuming normal use. The operator-managed PostgreSQL
Secret `fluxer-pgsql-pguser-fluxer` should also be backed up with the database.
1Password updates refresh `fluxer-env`; Reloader restarts workloads that reference
it. Coordinate rotations with backing services.

To update, review upstream deployment changes and update the per-container image
tags in `app/helmrelease.yaml`. Track configuration, probes, shard discovery and
routing changes in the corresponding local manifests; app-template does not
supply Fluxer-specific defaults. Lint and render with app-template before merging.
Meilisearch uses a read-only root filesystem, writable temporary storage at `/tmp`
and its persistent volume at `/meili_data`. `MEILI_UPGRADE_DB=true` allows supported
database migrations on startup when its pinned image version is updated.
A new Postgres major needs a dump/restore.

All application resource names use `fluxer` or a `fluxer-` prefix, including
workloads, Services and ConfigMaps. Internal DNS, gateway discovery and startup
checks use the prefixed Service names. Persistent claims are named
`data-fluxer-nats-0` and `data-fluxer-meilisearch-0`.

If an earlier release with unprefixed workload names was deployed, this rename
creates new StatefulSets and PVC names. Migrate or restore the existing data into
the prefixed claims before deploying; retained old claims are not reused
automatically. Preserve Secrets during the migration.

Upstream operational guidance: [Kubernetes](https://docs.fluxer.app/operator/kubernetes/)
and [reverse proxy requirements](https://docs.fluxer.app/operator/reverse-proxy/).

## Redundancy and maintenance

The API, gateway, HTTP proxies, push service and five service routers run two
replicas each, with required anti-affinity and a disruption budget retaining one
available replica. The gateway uses its existing Erlang clustering and graceful
handoff. The shared Envoy configuration also runs two replicas per gateway with
node spreading and a disruption budget.

NATS has three servers and `JOBS` / `JOBS_DLQ` use three-way JetStream replication.
Replication is durable stream configuration; there is no scheduled reconciliation
job. Fluxer creates new streams with one replica, so restore three-way replication
after deleting/recreating streams or restoring a fresh NATS deployment. Preserve
the existing PVCs and stream/consumer state during normal upgrades.

PostgreSQL has three instances with required node anti-affinity. Dragonfly has a
primary and two operator-managed replicas across the nodes. Dragonfly replication
is asynchronous and its pods have no persistent snapshots.

Both LiveKit pods share the signalling Service, while each media Service selects
one StatefulSet ordinal. Public TCP/UDP ports must keep reaching the matching
ordinal's VIP; do not load-balance both media servers behind the same port pair.
LiveKit has a five-hour termination grace period so a planned drain can wait for
rooms to empty. A hard failure of the server hosting a room still interrupts that
room and requires client reconnection. Liveness checks the local TCP listener;
readiness checks LiveKit's health endpoint so a Redis outage does not trigger
fleet-wide liveness restarts.

This setup adds redundancy to supported components. The five Rust service shards,
the scheduler worker, and Meilisearch remain singletons. They recover through
Kubernetes rescheduling and may interrupt their functions during node failure;
this configuration does not implement redundant copies of a logical service shard.
The NAS and router also remain shared infrastructure dependencies.
