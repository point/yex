import Config

config :sync_test, SyncTest.Endpoint,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  pubsub_server: SyncTest.PubSub,
  live_view: [signing_salt: "aaaaaaaa"]

config :logger, level: :debug

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
