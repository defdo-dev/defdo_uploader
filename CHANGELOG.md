# Changelog

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
