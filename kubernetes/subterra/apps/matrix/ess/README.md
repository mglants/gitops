# Element Server Suite

The official `matrix-stack` OCI chart is pinned to 26.10.2. It manages Synapse,
HAProxy worker routing, Matrix Authentication Service (MAS), Element Web,
Element Admin, MatrixRTC authorization and LiveKit. Chart Ingress resources
are removed by a Helm post-renderer; Envoy HTTPRoutes provide public access.

| Host | Service |
| --- | --- |
| `matrix.glants.xyz` | Matrix client and federation APIs |
| `matrix-auth.glants.xyz` | MAS sign-in, accounts and OAuth |
| `element.glants.xyz` | Element Web |
| `matrix-admin.glants.xyz` | Element Admin |
| `matrix-rtc.glants.xyz` | MatrixRTC authorization and SFU |
| `glants.xyz/.well-known/matrix/*` | Client and federation discovery |

Compatibility login/logout/refresh requests go to MAS. Other Matrix requests
use the chart's HAProxy routing to three client readers and the sync,
federation, appservice and pusher workers. Other root-domain paths continue
through Envoy's existing nginx fallback.

ExternalDNS watches HTTPRoutes and inherits `ingress-ext.ur30.dev` from the
parent Gateway: public DNS reaches 193.41.79.236 and internal DNS reaches
192.168.40.2. The existing apex A record points directly to 193.41.79.236;
Cloudflare proxying was disabled so Matrix discovery is accessible to clients.

The shared Dragonfly component creates `ess-dragonfly` with its defaults:
one replica, no password, no snapshots. Synapse uses database 0, RTC
authorization database 2 and LiveKit database 3. These separate key spaces,
without access isolation. Active-call state is ephemeral.

Matrix LiveKit retains Cilium LoadBalancer 192.168.40.29: TCP 7885 and UDP 7886.
The router forwards these ports without translation. Shared coturn in
`networking` provides TURN, including TLS on 443 through Envoy. Fluxer's
separate LiveKit instances retain their existing configuration.

## Preserved data and credentials

PostgreSQL `synapse-pgsql`, existing Synapse and bridge databases, and media PVC
`synapse-data-v2` are retained. Their manifests are protected from Flux pruning.
MAS has its own database and role. It needs schema privileges in that database:

```sql
GRANT USAGE, CREATE ON SCHEMA public TO mas;
```

Media is stored at PVC-relative `media_store/`, owned by ESS UID/GID 10091.
The ESS Kopiur component backs up that PVC using the same UID/GID. Existing
PostgreSQL pgBackRest backups remain configured.

1Password `subterra/ess` holds the preserved signing key, Authentik client
secret and registration shared secret, plus persistent MAS encryption/shared
secrets, RSA/P-256 private keys and Synapse macaroon secret. ExternalSecret
`ess` renders application configuration and imports the existing `matrix-rtc`,
`coturn` and shared SMTP credentials. Administrator credentials remain in
`subterra/Matrix admin`; admin privileges reside in the migrated accounts.
The old Synapse 1Password item is archived.

Authentik retains client ID `matrix` and provider mapping `oidc-authentik`.
Its MAS callback is:
`https://matrix-auth.glants.xyz/upstream/callback/01K7R5DKD0E2Z0F8TDS4E5VYZM`.
Local password login remains enabled; public registration is disabled.

Telegram and Google Messages remain separate bridge applications. Their
ExternalSecret templates contain configuration; 1Password contains individual
credentials. Both connect to `http://ess-synapse:8008`.

## Migration completed on 2026-10-18

The PostgreSQL full backup `ess-pre-migration-20261018` succeeded before
migration. Media snapshot `synapse-media-pre-ess-20261018` was Ready before the
in-place media directory rename. Both are retained for recovery.

The official three-stage syn2mas procedure passed: dry run, real import,
then delegated authentication finalization. Fifteen accounts, two upstream
identity links, access/refresh tokens and devices were imported; 1,009
application-service users were skipped by the migrator as expected. The
`MATRIX_STACK_MSC3861` deployment marker is now `delegated_auth`. Returning to
legacy authentication requires restoring data; a Helm rollback is insufficient.

For an initial ESS install importing legacy authentication, seed the marker
with `legacy_auth` before the dry-run job. During the real OIDC import retain
the old OIDC configuration and temporarily disable the Synapse config-check
hook. After import, remove that configuration, restore the hook and disable
syn2mas. None of these temporary settings belong in the steady-state values.

## Validation

Helm lint, chart schema/template checks, Kustomize rendering and route backend
checks passed. ESS became Ready and all six HTTPRoutes were accepted by Envoy.
The preserved administrator token and password login passed. Three temporary
users passed native and OpenID RTC authorization and received audio in a
three-participant call through shared coturn, including TLS-only relay.
A nonmember was rejected with HTTP 403. Test sessions were revoked, test users
locked, and the temporary room removed. This media test did not verify
end-to-end encryption in Element clients or interactively complete Authentik SSO.
Telegram’s pre-existing crash was traced to its obsolete `relaybot` permission
and localhost listener. Its template now uses `relay` and binds 0.0.0.0; obsolete
Python logging settings were removed. SMTP uses the shared credentials with
TLS on port 465, matching other applications.

Upstream: [ESS migration](https://github.com/element-hq/ess-helm/blob/26.10.2/docs/migrating.md),
[syn2mas](https://github.com/element-hq/ess-helm/blob/26.10.2/docs/syn2mas.md).
