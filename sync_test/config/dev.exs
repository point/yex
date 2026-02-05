import Config

config :sync_test, SyncTest.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  server: true

config :phoenix, :stacktrace_depth, 20
