# Changelog

## 0.1.5 — 2026-07-23

- deps: `defdo_vault` 0.10.1 (V10 migrator — `vault_integrations.secret_id`
  index).
- ci: route CI to the linux/amd64 docker agent (revert local-backend hack).

## 0.1.4 — 2026-07-17

- deps: bump `defdo_vault` to 0.10.0, `defdo_tenant` to 0.10.3,
  `defdo_tenant_boundary` to 0.2.3, `phoenix_live_view` to 1.2.7, and `req` to
  0.6.3 (hex.outdated green). Compile + tests green.

## 0.1.3 — 2026-06-30

- deps: switch `req_s3` to `defdo_s3 ~> 0.1.0`

## 0.1.2 — 2026-06-30

- Switch `req_s3` to GitHub ref for `req ~> 0.6` support.
- Relax `req` to `~> 0.5 or ~> 0.6`.

## 0.1.1 — 2026-06-26

- Fix: include `VERSION` file in Hex package so `mix.exs` can read it at
  compile time.

## 0.1.0 — 2026-06-26

- Initial release.
- `Defdo.Uploader.Adapter` behaviour.
- `Defdo.Uploader.Adapters.S3` — S3/R2/MinIO via `req_s3`.
- `Defdo.Uploader.CredentialsBackend` behaviour + `DefaultBackend`.
- `Defdo.Uploader.VaultBackend` — encrypted credential storage via `defdo_vault`.
- `Defdo.Uploader.S3Credentials` — facade with 3 deployment levels.
- `Defdo.Uploader.CredentialsForm` — embeddable LiveComponent admin form.
- Tenant-aware via optional `defdo_tenant`.
