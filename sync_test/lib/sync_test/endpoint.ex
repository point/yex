defmodule SyncTest.Endpoint do
  use Phoenix.Endpoint, otp_app: :sync_test

  socket "/socket", SyncTest.UserSocket,
    websocket: true,
    longpoll: false

  plug Plug.Static,
    at: "/",
    from: :sync_test,
    gzip: false,
    only: ~w(index.html assets)

  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason

  plug SyncTest.Router
end
