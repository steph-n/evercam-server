defmodule EvercamMedia.ONVIFControllerMediaTest do
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

  test "GET /v2/onvif/v20/Media/GetProfiles, returns profile information", context do
    use_cassette "get_profiles" do
      conn = get build_conn(), "/v2/onvif/v20/Media/GetProfiles?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      [profile_1, _, _] = json_response(conn, 200) |> Map.get("Profiles")
      assert Map.get(profile_1, "token")  == "Profile_1"
    end
  end

  test "GET /v2/onvif/v20/Media/GetServiceCapabilities, returns profile information", context do
    use_cassette "media_get_service_capabilities" do
      conn = get build_conn(), "/v2/onvif/v20/Media/GetServiceCapabilities?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      snapshot_uri = json_response(conn, 200) |> Map.get("Capabilities") |> Map.get("SnapshotUri")
      assert snapshot_uri == "true"
    end
  end

  test "GET /v2/onvif/v20/Media/GetSnapshotUri, returns snapshot uri", context do
    use_cassette "get_snapshot_uri" do
      conn = get build_conn(), "/v2/onvif/v20/Media/GetSnapshotUri?#{@access_params}&ProfileToken=Profile_1&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      snapshot_uri = json_response(conn, 200) |> Map.get("MediaUri") |> Map.get("Uri")
      assert snapshot_uri == "http://192.168.1.100:8100/onvif-http/snapshot?Profile_1"
    end
  end

  test "GET /v2/onvif/v20/Media/GetVideoAnalyticsConfigurations", context do
    use_cassette "get_video_analytics_configuration" do
      conn = get build_conn(), "/v2/onvif/v20/Media/GetVideoAnalyticsConfigurations?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      token = json_response(conn, 200) |> Map.get("Configurations") |> Map.get("token")
      assert token == "VideoAnalyticsToken"
    end
  end

  test "GET /v2/onvif/v20/Media/GetVideoSources", context do
    use_cassette "get_video_sources" do
      conn = get build_conn(), "/v2/onvif/v20/Media/GetVideoSources?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      video_source = json_response(conn, 200) |> Map.get("VideoSources") |> Map.get("token")
      assert video_source == "VideoSource_1"
    end
  end

  test "GET /v2/onvif/v20/Media/GetSnapshotUri using camera_id", context do
    use_cassette "get_snapshot_uri_from_db" do
      conn = get build_conn(), "/v2/onvif/v20/Media/GetSnapshotUri?id=recorded-response&ProfileToken=Profile_1&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      snapshot_uri = json_response(conn, 200) |> Map.get("MediaUri") |> Map.get("Uri")
      assert snapshot_uri == "http://192.168.1.100:8100/onvif-http/snapshot?Profile_1"
    end
  end
end
