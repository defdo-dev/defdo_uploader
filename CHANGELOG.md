# Changelog

## 0.3.0

A minor, for three reasons that each would have been enough: new public API
(`Defdo.Uploader.Storage` and the policy modules), a behaviour change visible
to consumers (`delete_object/2` now reports refused deletes), and two raised
floors.

### Requirement floors

| requirement | was | now |
|---|---|---|
| `defdo_tenant` (optional) | `~> 0.15` | `~> 0.16` |
| `defdo_vault` (optional) | `~> 0.14` | `~> 0.16` |

Both were resolving 0.16.0 in every host that will adopt this release —
defdo_auth, defdo_cms and defdo_theme already lock both — so the floor now
states what is actually built and tested. defdo_theme_hub locks vault 0.15.1;
its `~> 0.2` requirement admits this release, and taking it moves vault to
0.16.0 there too. Note that 0.16.0 of defdo_vault requires Flop `~> 0.29`.

**Reaches `~> 0.2` consumers without a requirement change.** A two-segment
`~> 0.2` caps at the next major, so theme_hub, cms and my_mvno pick this
release up on their next `mix deps.update defdo_uploader`, including the
`delete_object/2` change below.

### Policy storage: one upload path for tenant, user and platform assets

`Defdo.Uploader.Storage` runs an upload through a **kind** — a policy that
decides ownership, visibility, accepted types, size and pixel limits, and the
variants stored. theme, cms and defdo_auth previously had no shared answer to
any of these; each built its own keys, and nothing re-encoded what users sent.

| Module | Responsibility |
|---|---|
| `Kind` | built-in `:tenant_logo`, `:tenant_background`, `:user_picture`, `:platform_icon`; override or add via `config :defdo_uploader, :kinds` |
| `Guard` | size cap, type sniffed from magic bytes, SVG refused unless the kind allows it |
| `Key` | `tenants/<tenant>/...` versioned keys; tenant from `Defdo.Tenant.Context`, explicit tenant must agree with it; segments validated against traversal |
| `ImagePipeline` | re-encode every variant, autorotate, strip metadata, never upscale, flatten JPEG onto white, reject decompression bombs by pixel count |
| `Storage` | `put/3` with rollback of partial writes, `url/3` public or presigned, idempotent `delete/2`, `negotiate/2` on `Accept`, `fetch_local/3` lazy hydration |

**WebP, measured on real images from this estate** (quality 80–90):

| Asset | Fallback | WebP | Saving |
|---|---|---|---|
| logo, 512px | PNG 45.8 KB | 39.7 KB | 13% |
| photo, avatar 512 | JPEG 83.0 KB | 69.6 KB | 16% |
| photo, background | JPEG 334.5 KB | 265.7 KB | 21% |
| photo, background | JPEG 158.9 KB | 69.8 KB | 56% |
| photo, avatar 512 | JPEG 25.8 KB | 13.4 KB | 48% |

Web-facing kinds store WebP **and** a PNG/JPEG fallback, served by `Accept`:
Outlook and some native apps cannot decode WebP. `:platform_icon` never
produces WebP, because iOS app icons, `apple-touch-icon`, Play Store listings
and favicons require PNG.

**Security properties, each with a test that was verified to fail when the
protection is removed:** SVG refused for user uploads; `..` and separators
rejected in key segments; explicit tenant cannot override the context tenant;
EXIF (where camera GPS lives) stripped — the test asserts the source really
carries EXIF first; appended polyglot bytes dropped; cache paths cannot escape
the cache directory; pixel-count cap enforced before decode.

**Adapter:** `Adapters.S3` gains `put_object/5` (explicit content type and
`Cache-Control`), `get_object/2` and `presign_get/3`. They are
`@optional_callbacks` on `Defdo.Uploader.Adapter`, so 0.2 adapters still
compile.

**New optional dependency:** `{:image, "~> 0.72"}`. Without it
`ImagePipeline.render/2` returns `{:error, :image_library_unavailable}` rather
than storing an unprocessed upload.

**Docs:** README and `docs/architecture.md` described a 4-arity
`upload_file`, a `config :defdo_uploader, :adapter` key and `req_s3` — none of
which exist. Corrected.

### The S3 adapter no longer reports a refused request as success

`Req` returns `{:ok, response}` for every HTTP status, and the adapter only
ever matched `{:ok, _}`:

- **`delete_object/2`** returned `:ok` on a 403 or 500. Consumers such as
  `ManagedProjectAssets.delete_asset` in defdo_theme_hub and
  `ProjectAssets.delete_asset` in defdo_cms delete their database row only when
  storage answers `:ok`, so every refused delete orphaned its object. It now
  returns `{:error, {:http_status, status}}`; a **404 stays `:ok`**, because a
  missing object is already the state a delete asks for.
- **`upload_file/3`** let a refused PUT fall through to `head_object/2`. When
  an older object already existed at that key, HEAD found it and the upload
  reported success with the old object's metadata.
- **`upload_one/4`** ignored the PUT status entirely.

**Visible to consumers:** a delete that storage refuses now leaves the row in
place instead of removing it. That is the point — the row is the only record
of an object that still exists — but code that assumed delete always succeeds
will now see the error.

**Unchanged on purpose:** `upload_file/3` still ignores the prefix in a
`"bucket/prefix"` bucket. defdo_theme_hub and defdo_cms already join the prefix
into the object key, and their tests assert that layout; applying it here too
would write to `prefix/prefix/...`.

### The adapter has tests

`client/1` merges an optional `:req_options` from the config map into the base
request, so the adapter runs against `Req.Test` stubs with no network.
`Adapters.S3` previously had zero tests. The four behaviour tests above were
verified to fail against the old adapter, not merely to pass against the new
one.

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
