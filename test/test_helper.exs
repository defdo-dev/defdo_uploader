# Configure test endpoint
Application.put_env(:defdo_uploader, Defdo.Uploader.TestEndpoint,
  server: false,
  secret_key_base: String.duplicate("a", 64),
  live_view: [signing_salt: "test-salt"]
)

Application.put_env(:defdo_uploader, :credentials_backend, Defdo.Uploader.DefaultBackend)

# Start a local PubSub for tests
{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: Defdo.Uploader.PubSub)

ExUnit.start()

{:ok, _} = Defdo.Uploader.TestEndpoint.start_link()
