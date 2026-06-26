import Config

config :defdo_uploader, :credentials_backend, Defdo.Uploader.DefaultBackend

config :phoenix, :json_library, Jason

config :defdo_uploader, Defdo.Uploader.TestEndpoint,
  server: false,
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "test-salt"]
