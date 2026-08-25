# Changelog

## 0.2.0

### Every requirement declares the line it resolves on

This package was the furthest behind in the defdo_theme_hub dependency
closure — nine requirements, and six defdo packages that moved several minors
each while the requirements never complained.

**Unbounded** — a `>=` with no ceiling accepts every version ever published:

- `phoenix_live_view` `>= 1.0.0` -> `~> 1.2`
- `ex_doc` `>= 0.0.0` -> `~> 0.40`
- `floki` `>= 0.36.0` -> `~> 0.38`
- `lazy_html` `>= 0.1.0` -> `~> 0.1`

**Accumulated** — `req` `~> 0.5 or ~> 0.6` -> `~> 0.7`.

**defdo parents**, all released today ahead of this one so these floors are
correct on the first try rather than the second:

| requirement | was | now | jump |
|---|---|---|---|
| `defdo_tenant` | `~> 0.10` | `~> 0.15` | 0.13.1 -> 0.15.0 |
| `defdo_vault` | `~> 0.10` | `~> 0.14` | 0.11.0 -> 0.14.0 |
| `defdo_tenant_boundary` | `~> 0.2` | `~> 0.4` | 0.2.7 -> 0.4.0 |
| `defdo_s3` | `~> 0.1.0` | `~> 0.2` | 0.1.2 -> 0.2.0 |

### What the verification here actually proves

4 tests in a single test file. That is thin for a release that moves six defdo
packages, so `mix compile --warnings-as-errors` was run against a forced
rebuild as the real signal, and it is clean. The green suite is not the
evidence; the clean compile against the new dependency set is.

**Consumers must edit to follow.** `defdo_theme_hub` declares
`defdo_uploader ~> 0.1.1` and `defdo_cms` declares `~> 0.1.3` — both
three-segment, capping at `< 0.2.0`.

`mix hex.outdated` empty. `mix deps.unlock --check-unused` clean after dropping
`bandit` and `thousand_island`, which no requirement reached.

## 0.1.7 — 2026-07-26

### Security

- Cleared every advisory `mix hex.audit` reported for this package. Only locked
  versions moved; no dependency requirement changed, so this is a drop-in
  upgrade.

### Changed

- Tracks `defdo_tenant` 0.10.4, `defdo_tenant_boundary` 0.2.4 and `defdo_vault`
  0.10.2, all security releases. `defdo_tenant` also dropped its `bypass` test
  dependency, which kept `plug_cowboy`, `cowboy`, `cowlib` and `ranch` — a
  second HTTP server — in the tree of anything building its test environment.

## 0.1.6 — 2026-07-23

- deps: adopt `defdo_vault ~> 0.10` (V10 migrator). Raises the declared
  constraint floor from `~> 0.9`; lock stays at 0.10.1.

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
