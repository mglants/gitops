# BigBlueButton 4.0 on Subterra

Enabled for deployment through Flux and registered in the parent apps
Kustomization. Uses the existing `apps` namespace; no Namespace is created.

## Files and ownership

- `ks.yaml`: Flux dependencies, the existing Dragonfly and Kopiur components,
  and a Kopiur source-list patch covering the three application data PVCs.
- `app/helmrelease.yaml`: bjw-s app-template 5.0.1 controllers, Services,
  ConfigMaps, retained PVCs, Envoy HTTPRoutes and BackendTrafficPolicy.
- `app/externalsecret.yaml`: individual 1Password fields rendered by External
  Secrets v2, including the LiveKit configuration. No configuration YAML belongs
  in 1Password.
- `app/postgrescluster.yaml`: dedicated PGO PostgreSQL 16 cluster, two instances,
  operator-generated passwords and existing pgBackRest/NAS backup conventions.

The first trial uses one replica per application controller and `Recreate`
updates. Media and its recorder share one pod. LiveKit is dedicated to BBB and
pinned to 1.13.10; existing Matrix and Fluxer deployments are untouched.
The optional Gladia STT and LiveKit SIP containers are present but disabled.
Enable them only after arranging provider credentials and, for SIP, its media
and signaling exposure. The transcription plugin assets are included.

## Images

The bootstrap image needs the new baked-in `bbb-bootstrap` command prepared in
`containers/apps/bigbluebutton-bootstrap/`; publish that image change before
activation. The chart no longer contains Python in a ConfigMap.

All custom images use `ghcr.io/mglants/bigbluebutton-<component>:4.0.0`, matching
CI's published semantic tags (without the source tag's `v` prefix). Publish the
reviewed containers commit before activation and verify every enabled image can
be pulled from Subterra. Pin the published digests before treating the deployment
as an immutable release; the version tags can be rebuilt with changed companion
sources. Private packages require a separately configured image pull secret.

Greenlight, Hasura and LiveKit use the audited official images with digest pins.
Dragonfly's image and resource settings come unchanged from the component.
There is no separate Redis controller, Service or PVC in the chart.

## Hosts and media networking

Proposed public hosts:

| Host              | Purpose                                                                          |
| ----------------- | -------------------------------------------------------------------------------- |
| `bbb.glants.xyz`  | BBB API, HTML5 client, WebSockets, LiveKit signaling, playback and plugin assets |
| `meet.glants.xyz` | Greenlight room management and local authentication                              |

Both HTTPRoutes attach to `networking/envoy-external`, listener `https`.
ExternalDNS uses `ingress-ext.ur30.dev` as their target: the existing split DNS
publishes public `193.41.79.236` and internal `192.168.40.2` for that target.
The existing wildcard certificate covers both hosts. Greenlight uses the same
public BBB API endpoint for server requests and browser join links; there is no
join-URL rewriting or private Service URL exposed to browsers.

`192.168.40.30` was unused when checked and is proposed for the Cilium media
LoadBalancer. It has not been allocated by this preparation. Recheck availability
before activation. Forward these ports, preserving port numbers:

| Public port | Destination                                        |
| ----------- | -------------------------------------------------- |
| TCP 7887    | `192.168.40.30:7887` — LiveKit ICE/TCP             |
| UDP 7888    | `192.168.40.30:7888` — LiveKit multiplexed ICE/UDP |

Keep existing TCP 80/443 forwarding to Envoy. Reuse shared coturn's existing
3480, 5349, TLS-on-443 and relay-range forwards; no new TURN server is installed.
LiveKit advertises the public IP and its internal address. The recorder connects
through localhost in the media pod. Validate LAN/public-address NAT reflection
and calls from a mobile/external network during acceptance testing.

Do not increase media replicas behind this single Service: direct media must
reach the LiveKit instance which owns the session. Multi-instance media needs a
separate routing/port-allocation design.

## Required secrets

Create a `bigbluebutton` item in the same 1Password vault used by the existing
`onepassword-connect` ClusterSecretStore. It needs these individual fields:

| Field             | Value                                                          |
| ----------------- | -------------------------------------------------------------- |
| `SHARED_SECRET`   | Persistent BBB API secret; use at least 32 random bytes        |
| `HASURA_SECRET`   | Persistent Hasura administrative secret                        |
| `LIVEKIT_KEY`     | Stable LiveKit API key identifier, for example `bigbluebutton` |
| `LIVEKIT_SECRET`  | Persistent random LiveKit API secret, at least 32 bytes        |
| `SECRET_KEY_BASE` | Greenlight Rails secret; use 64 random bytes encoded as hex    |
| `GLADIA_API_KEY`  | Optional provider-issued key; only required when enabling STT  |

Existing `smtp` and `coturn` items supply SMTP credentials and
`TURN_SHARED_SECRET`; do not duplicate those credentials. SMTP uses the existing
implicit TLS convention on port 465. The generated Secret is orphaned/retained
when its ExternalSecret is deleted. Keep these values stable across redeploys.

PGO generates database passwords; do not add database passwords to 1Password.
BBB gets its own role and three databases (`bbb_graphql`, `blocknote_app`,
`hasura_app`); Greenlight has a separate non-superuser role/database. The BBB role
uses the repository's SUPERUSER convention to install required extensions.

Greenlight uses Authentik OIDC with application/client ID `bigbluebutton` and
issuer `https://authentik.glants.xyz/application/o/bigbluebutton/`. The provider's
strict callback URL is `https://meet.glants.xyz/auth/openid_connect/callback`.
The client secret comes from `OPENID_CONNECT_CLIENT_SECRET` in the `bigbluebutton`
1Password item; the client ID is plain chart configuration. OIDC disables normal
local password login. Assign Greenlight administrator roles separately.

## Initialization and upgrades

The chart has a post-install/post-upgrade bootstrap Job. Helm's workload wait is
disabled so that the Job can initialize schemas while apps/notes wait in their
init containers. Helm still waits for its hook Job; this Job's success does not
prove all application pods are healthy.

The Job runs `bbb-bootstrap all` from the bootstrap image, waits for PGO, loads schemas from the **same bootstrap image version**,
then applies Hasura metadata and checks consistency. Fresh databases are
initialized transactionally. A stored schema digest makes repeated bootstrap
safe. Unknown existing schemas and changed source schemas are rejected; no
DROP DATABASE or reset runs. Apps/notes also compare their expected schema digest
before starting. Hasura's CLI downloads its matching CLI extension on first use,
so bootstrap needs outbound HTTPS and executable writable `/tmp` (EmptyDir).

Greenlight separately precompiles assets and applies Rails migrations in init
containers, with writable EmptyDirs/PVCs and a non-root user. The main process
runs Rails directly. A small Git-managed initializer fixes Greenlight 3.9's BBB
4 health-check meeting ID. Public API requests retain checksum authentication.
The native SMTP health check is disabled because it does not support implicit TLS
on port 465; application email still uses TLS, and DB/Redis/BBB checks remain enabled.

Drain meetings before upgrading the stack. If schema digests change, take and
verify backups and perform the upstream migration explicitly before resuming.
Do not delete the marker or replace databases merely to bypass the guard.
This is a coordinated single-instance trial, not an HA/rolling-upgrade design.

## Storage and backups

| Claim                              | Class/access         | Initial size | Contents                                                          |
| ---------------------------------- | -------------------- | ------------ | ----------------------------------------------------------------- |
| `bigbluebutton-media`              | `truenas-nfs`, RWX   | 100Gi        | Presentations, recording status, published/unpublished recordings |
| `bigbluebutton-capture`            | `truenas-nfs`, RWX   | 100Gi        | Raw recorder media used by processing workers                     |
| `bigbluebutton-greenlight-storage` | `truenas-iscsi`, RWO | 5Gi          | Greenlight uploads/ActiveStorage                                  |

The Helm PVCs have `helm.sh/resource-policy: keep`. The PGO cluster is protected
from Flux pruning and has its own 20Gi-per-instance iSCSI storage. Review NAS
capacity and UID/GID 10001 permissions before activation. The gateway frontend
mounts published media read-only. Processing workers retain write access to raw
capture so native cleanup can work.

The existing **Kopiur backup component** covers all three application claims,
using its NAS repository, CSI snapshots, daily retention and verification
schedules. The mover runs as UID/GID/fsGroup 10001. PostgreSQL uses pgBackRest with
`/bigbluebutton/repo1` in the existing `crunchy-postgres` bucket. No Kasten labels
or resources are used. Validate both database and media restores before relying
on these backups; snapshots of an active capture may contain an incomplete file.

Dragonfly uses the component defaults: one replica, no password and no snapshot
persistence. A cold restart loses Redis-compatible state, including queue state
and sessions. Durable media and PostgreSQL survive independently. Drain meetings
before planned restarts and verify/recover unfinished recordings afterwards.

## Review and activation

1. Review these files, hostnames, media IP/ports, resources and NAS sizes.
2. Publish the custom images and confirm cluster pull access.
3. Create the required 1Password fields; review backup repository availability.
4. Arrange the media forwards and test the existing TURN endpoint.
5. After approval, register `./bigbluebutton/ks.yaml` in the parent apps
   Kustomization, set both `spec.suspend` fields to `false`, and commit/push the
   reviewed GitOps changes.
6. Reconcile and watch PGO, the bootstrap hook Job, all deployments, HTTPRoutes,
   ExternalSecret, PVCs and Kopiur policies. Confirm NFS write permissions and
   workload memory behavior; declared resources are provisional trial budgets.
7. Create a Greenlight account and promote it with the upstream task, for example
   `kubectl -n apps exec deploy/bigbluebutton-greenlight -c app -- bundle exec rake 'user:set_admin_role[email@example.com]'`.
8. Test meetings with multiple browsers, microphone/camera, screen share, notes,
   whiteboard, document upload/conversion, recording processing, interactive
   playback and MP4 download. Include external/mobile clients, TURN fallback,
   an orderly restart and backup/restore testing.

Do not expose PostgreSQL, Dragonfly, Hasura's administrative endpoint, bootstrap
or recording workers publicly. Their Services/configuration are internal.

## Local validation

Build the Flux overlay without contacting the cluster:

```sh
flux build kustomization cluster-apps-bigbluebutton \
  --path kubernetes/subterra/apps/apps/bigbluebutton/app \
  --kustomization-file kubernetes/subterra/apps/apps/bigbluebutton/ks.yaml \
  --dry-run --strict-substitute
```

Extract `spec.values` from the HelmRelease for `helm lint`/`helm template`, using
app-template 5.0.1 and API capability `gateway.networking.k8s.io/v1/HTTPRoute`.
Preparation validation uses Subterra server-side dry-run only. It does not create
any resources, reserve an IP, change DNS/router forwards or create credentials.
