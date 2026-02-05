import Config

config :sync_test, SyncTest.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: true
