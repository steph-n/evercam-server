use Mix.Config

config :evercam_media,
  start_camera_workers: false

config :evercam_media,
  start_evercam_bot: false

config :evercam_media,
  start_timelapse_workers: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :evercam_media, EvercamMediaWeb.Endpoint,
  http: [port: 4001],
  server: false,
  email: "evercam.io <env.test@evercam.io>"

# Do not create intercom user in test mode
config :evercam_media, :create_intercom_user, false

# Start spawn process or not
config :evercam_media, :run_spawn, false

# Print only warnings and errors during test
config :logger, level: :warn

config :evercam_media,
  storage_dir: "tmp/storage",
  dummy_auth: "foo:bar"

config :evercam_media, ecto_repos: [EvercamMedia.Repo]

# Configure your database
config :evercam_media, EvercamMedia.Repo,
  username: "postgres",
  password: "postgres",
  database: "evercam_tst",
  pool: Ecto.Adapters.SQL.Sandbox,
  types: EvercamMedia.PostgresTypes

config :evercam_media, EvercamMedia.SnapshotRepo,
  username: "postgres",
  password: "postgres",
  database: "evercam_tst",
  pool: Ecto.Adapters.SQL.Sandbox

config :exvcr,
  [
    vcr_cassette_library_dir: "test/fixtures/vcr_cassettes",
    custom_cassette_library_dir: "test/fixtures/custom_cassettes",
    filter_sensitive_data: [
      [pattern: "<PASSWORD>.+</PASSWORD>", placeholder: "PASSWORD_PLACEHOLDER"]
    ],
    filter_url_params: false,
    response_headers_blacklist: [],
  ]

