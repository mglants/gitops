# Remnashop 1.0 migration

This deployment uses Flux, not Docker Compose. Before reconciling the updated
HelmRelease:

1. Verify a current, restorable PostgreSQL backup and preserve the existing
   `APP_CRYPT_KEY` in the `remnawave-bot` 1Password item. Add a separate,
   persistent `APP_JWT_SECRET` of at least 32 characters to that item and wait
   for External Secrets to synchronize it.
2. Stop the old bot workload and ensure its pod has terminated. Upgrade the
   panel to 3.x and wait until it is healthy before starting the new bot. The
   single HelmRelease contains both changes, so an ordinary reconciliation alone
   does not guarantee this ordering; stage the panel upgrade separately.
3. Reconcile the new bot after the panel is healthy. Its API migrates the old
   database automatically and saves a pre-migration dump under the bot PVC's
   `media/backups` directory. The other processes wait for API readiness. Check
   the migration report and logs before proceeding.
4. Register the owner account in the dashboard, configure the Telegram bot token
   there, and restart the Telegram process. The old token environment variables
   are ignored by the new version. Verify Telegram, panel and payment webhooks.

The old assets remain in the PVC's `data` directory; new media and backups use
`media`. The upstream Compose `--remove-orphans` step does not apply to Kubernetes.
The development image tags are mutable and are pulled on pod creation.

Upstream: https://github.com/remnashop/remnashop/blob/dev/docker-compose.prod.internal.yml

## Panel 2.8 to 3.x

- Back up the panel database and its 1Password configuration before upgrading.
  The manifest maps the existing `JWT_AUTH_SECRET` to `APP_SECRET` without
  changing its value. Verify that the existing item contains that key before
  reconciliation. The former `JWT_API_TOKENS_SECRET`, `SWAGGER_PATH`,
  `SCALAR_PATH`, and `IS_DOCS_ENABLED` settings are obsolete.
- Upgrade and verify the panel first, then nodes. The in-cluster node is still
  pinned to 2.8.0; plan and test its upgrade separately. Newer node releases
  change Xray and can affect REALITY clients.
- The v3 API replaces user UUID identifiers with numeric IDs and changes or
  removes endpoints. Verify the temporary-subscription app, S3 sync, status
  checker, subscription page, and any external clients against v3 before relying
  on them. Compatibility has not been established by this manifest change.
- Existing subscription settings and token scopes are automatically migrated;
  verify subscription response headers and client behavior after upgrade.

References: https://f.docs.rw/t/topic/354 and https://docs.rw/install/upgrading/
