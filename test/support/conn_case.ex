defmodule EvercamMediaWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  imports other functionalities to make it easier
  to build and query models.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      use Phoenix.ConnTest

      # Alias the data repository and import query/model functions
      alias Evercam.Repo
      alias EvercamMedia.Message
      alias EvercamMedia.Endpoint
      # import Ecto.Model
      import Ecto.Query, only: [from: 2]

      # Import URL helpers from the router
      import EvercamMediaWeb.Router.Helpers

      # The default endpoint for testing
      @endpoint EvercamMediaWeb.Endpoint
    end
  end

  setup tags do
    # Wrap this case in a transaction
    Ecto.Adapters.SQL.Sandbox.checkout(Evercam.Repo)
    Ecto.Adapters.SQL.Sandbox.checkout(Evercam.SnapshotRepo)
    EvercamMedia.TestHelpers.invalidate_caches
    if tags[:onvif], do: seed_onvif_tests()

    :ok
  end

  def seed_onvif_tests do
    country = Evercam.Repo.insert! %Country{iso3166_a2: "ad", name: "Andorra"}
    user = Evercam.Repo.insert! %User{username: "dev", password: "dev", firstname: "Awesome", lastname: "Dev", email: "dev@localhost", country_id: country.id}
    Evercam.Repo.insert! %Camera{name: "Test Mobile Mast", exid: "mobile-mast-test", owner_id: user.id, is_online_email_owner_notification: false, is_public: false, config: %{snapshots: %{jpg: "/Streaming/Channels/1/picture"}, internal_rtsp_port: "", internal_http_port: "", internal_host: "", external_rtsp_port: 9100, external_http_port: 8100, external_host: "149.13.244.32", auth: %{basic: %{username: System.get_env["ONVIF_USER"],password: System.get_env["ONVIF_PASS"]}}}}
    Evercam.Repo.insert! %Camera{name: "EXVCR Camera", exid: "recorded-response", owner_id: user.id, is_online_email_owner_notification: false, is_public: false, config: %{snapshots: %{jpg: "/Streaming/Channels/1/picture"}, internal_rtsp_port: "", internal_http_port: "", internal_host: "", external_rtsp_port: 9100, external_http_port: 12345, external_host: "recorded_response", auth: %{basic: %{username: System.get_env["ONVIF_USER"],password: System.get_env["ONVIF_PASS"]}}}}
  end

  def parse_onvif_error_type(response) do
    response
    |> Map.get("Fault")
    |> Map.get("Code")
    |> Map.get("Subcode")
    |> Map.get("Value")
  end
end
