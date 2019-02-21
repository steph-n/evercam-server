defmodule EvercamMedia.ONVIFControllerImagingTest do
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

  test "GET /v2/onvif/v20/DeviceIO/GetImagingSettings", context do
    use_cassette "get_imaging_settings" do
      conn = get build_conn(), "/v2/onvif/v20/Imaging/GetImagingSettings?#{@access_params}&VideoSourceToken=VideoSource_1&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      brightness = json_response(conn, 200) |> Map.get("ImagingSettings") |> Map.get("Brightness")
      assert brightness == "50"
    end
  end

  test "GET /v2/onvif/v20/DeviceIO/GetServiceCapabilities", context do
    use_cassette "img_get_service_capabilities" do
      conn = get build_conn(), "/v2/onvif/v20/Imaging/GetServiceCapabilities?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      image_stabilization = json_response(conn, 200) |> Map.get("Capabilities") |> Map.get("ImageStabilization")
      assert image_stabilization == "false"
    end
  end
end
