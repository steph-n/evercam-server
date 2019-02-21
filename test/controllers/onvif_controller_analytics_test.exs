defmodule EvercamMedia.ONVIFControllerAnalyticsTest do
  use EvercamMediaWeb.ConnCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney, options: [clear_mock: true]

  @auth System.get_env["ONVIF_AUTH"]

  @moduletag :onvif
  @access_params "url=http://recorded_response&auth=#{@auth}"

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex), country_id: country.id})

    {:ok, user: user}
  end

  test "GET /v2/onvif/v20/Analytics/GetServiceCapabilities", context do
    use_cassette "get_service_capabilities" do
      conn = get build_conn(), "/v2/onvif/v20/Analytics/GetServiceCapabilities?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      analytics_module_support = json_response(conn, 200) |> Map.get("Capabilities") |> Map.get("AnalyticsModuleSupport")
      assert analytics_module_support == "true"
    end
  end

  test "GET /v2/onvif/v20/Analytics/GetAnalyticsModules", context do
    use_cassette "get_analytics_modules" do
      conn = get build_conn(), "/v2/onvif/v20/Analytics/GetAnalyticsModules?#{@access_params}&ConfigurationToken=VideoAnalyticsToken&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      [cell_motion_engine | _] = json_response(conn, 200) |> Map.get("AnalyticsModule")
      assert Map.get(cell_motion_engine, "Name") == "MyCellMotionModule"
    end
  end
end
