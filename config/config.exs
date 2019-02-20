# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :hackney,
  :timeout, 15000

# Configures the endpoint
config :evercam_media,
  bot_name: "testevercam_bot"

config :nadia,
  token: System.get_env("NADIA_TOKEN"),
  recv_timeout: 15

config :evercam_media, EvercamMediaWeb.Endpoint,
  check_origin: false,
  url: [host: "localhost"],
  secret_key_base: "joIg696gDBw3ZjdFTkuWNz7s21nXrcRUkZn3Lsdp7pCNodzCMl/KymikuJVw0igG",
  debug_errors: false,
  server: true,
  root: Path.expand("..", __DIR__),
  pubsub: [name: EvercamMedia.PubSub,
           adapter: Phoenix.PubSub.PG2]

config :evercam_media,
  mailgun_domain: System.get_env("MAILGUN_DOMAIN"),
  mailgun_key: System.get_env("MAILGUN_KEY")

config :evercam_media,
  ftp_domain: System.get_env("FTP_DOMAIN") |> to_charlist,
  ftp_username: System.get_env("FTP_USERNAME") |> to_charlist,
  ftp_password: System.get_env("FTP_PASSWORD") |> to_charlist

config :logger, :console,
  format: "$date $time $metadata[$level] $message\n",
  metadata: [:request_id]

config :evercam_media,
  hls_url: "http://localhost:8080/hls"

config :elixir_dropbox,
  upload_url: "https://content.dropboxapi.com/2/"

config :evercam_media,
  storage_dir: "storage"

config :evercam_media,
  files_dir: "data"

config :geoip, provider: :ipstack, use_https: :false, api_key: System.get_env("IPSTACK_ACCESS_KEY")

config :evercam_media,
  seaweedfs_url: "http://localhost:8888",
  seaweedfs_url_1: "http://localhost:8888",
  seaweedfs_url_new: "http://localhost:8888"

config :evercam_media, EvercamMedia.Mailer,
  adapter: Swoosh.Adapters.Mailgun,
  api_key: "sandbox",
  domain: "sandbox"

config :new_relic,
  application_name: System.get_env("NEWRELIC_APP_NAME"),
  license_key: System.get_env("NEWRELIC_LICENSE_KEY"),
  poll_interval: 60_000

config :ex_aws,
  access_key_id: System.get_env["AWS_ACCESS_KEY_ID"],
  secret_access_key: System.get_env["SECRET_ACCESS_KEY"],
  region: "eu-west-1"

config :evercam_media, :phoenix_swagger,
  swagger_files: %{
    "priv/static/swagger.json" => [
      router: EvercamMediaWeb.Router,
      endpoint: EvercamMediaWeb.Endpoint
    ]
  }

config :ex_aws, :hackney_opts,
  recv_timeout: 300_000

config :porcelain,
  goon_warn_if_missing: false

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
