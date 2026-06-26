defmodule Defdo.Uploader.TestEndpoint do
  @moduledoc false

  use Phoenix.Endpoint, otp_app: :defdo_uploader

  @session_options [store: :cookie, key: "_defdo_uploader_test", signing_salt: "test"]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])
end
