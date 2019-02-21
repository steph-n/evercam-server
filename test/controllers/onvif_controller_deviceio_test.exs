defmodule EvercamMedia.ONVIFControllerDeviceIOTest do
  use EvercamMediaWeb.ConnCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney, options: [clear_mock: true]

  @auth Application.get_env(:evercam_media, :dummy_auth)

  @moduletag :onvif
  @access_params "url=http://recorded_response&auth=#{@auth}"

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex), country_id: country.id})

    {:ok, user: user}
  end

  test "GET /v2/onvif/v20/DeviceIO/GetAudioOutputs", context do
    use_cassette "get_audio_outputs" do
      conn = get build_conn(), "/v2/onvif/v20/DeviceIO/GetAudioOutputs?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      token = json_response(conn, 200) |> Map.get("AudioOutputs") |> Map.get("token")
      assert token == "AudioOutputToken"
    end
  end

  test "GET /v2/onvif/v20/DeviceIO/GetAudioOutputConfiguration", context do
    use_cassette "get_audio_output_configuration" do
      conn = get build_conn(), "/v2/onvif/v20/DeviceIO/GetAudioOutputConfiguration?#{@access_params}&AudioOutputToken=AudioOutputToken&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      send_primacy = json_response(conn, 200) |> Map.get("AudioOutputConfiguration") |> Map.get("SendPrimacy")
      assert send_primacy == "www.onvif.org/ver20/HalfDuplex/Server"
    end
  end
end
