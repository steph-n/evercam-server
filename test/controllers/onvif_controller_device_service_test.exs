defmodule EvercamMedia.ONVIFControllerDeviceServiceTest do
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

  test "GET /v2/onvif/v20/device_service/GetDeviceInformation, returns meaningful info", context do
    use_cassette "get_device_information" do
      conn = get build_conn(), "/v2/onvif/v20/device_service/GetDeviceInformation?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      camera_model = json_response(conn, 200) |> Map.get("Model")
      assert camera_model == "DS-2DF7286-A"
    end
  end

  test "GET /v2/onvif/v20/device_service/GetNetworkInterfaces, returns meaningful info", context do
    use_cassette "get_network_interfaces" do
      conn = get build_conn(), "/v2/onvif/v20/device_service/GetNetworkInterfaces?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      enabled =  json_response(conn, 200) |> Map.get("NetworkInterfaces") |> Map.get("Enabled")
      assert enabled == "true"
    end
  end

  test "GET /v2/onvif/v20/device_service/GetCapabilities, returns meaningful info", context do
    use_cassette "get_capabilities" do
      conn = get build_conn(), "/v2/onvif/v20/device_service/GetCapabilities?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      device_xaddr = json_response(conn, 200) |> Map.get("Capabilities") |> Map.get("Device") |> Map.get("XAddr")
      assert device_xaddr == "http://192.168.1.100:8100/onvif/device_service"
    end
  end
end
