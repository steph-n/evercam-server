defmodule EvercamMedia.ONVIFControllerErrorsTest do
  use EvercamMediaWeb.ConnCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney, options: [clear_mock: true]
  import EvercamMediaWeb.ConnCase ,only: [parse_onvif_error_type: 1]

  @auth System.get_env["ONVIF_AUTH"]

  @moduletag :onvif
  @access_params "url=http://recorded_response&auth=#{@auth}"

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex), country_id: country.id})

    {:ok, user: user}
  end

  @tag :capture_log
  test "GET /v2/onvif/v20/DeviceIO/GetUnknownAction", context do
    use_cassette "error_unknown_action" do
      conn = get build_conn(), "/v2/onvif/v20/DeviceIO/GetUnknownAction?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      error_type = json_response(conn, 500) |> parse_onvif_error_type
      assert error_type == "ter:ActionNotSupported"
    end
  end

  @tag :capture_log
  test "bad credentials", context do
    use_cassette "error_bad_credentials" do
      conn = get build_conn(), "/v2/onvif/v20/device_service/GetNetworkInterfaces?url=http://recorded_response&auth=admin:foo&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      error_type = json_response(conn, 400) |> parse_onvif_error_type
      assert error_type == "ter:NotAuthorized"
    end
  end

  @tag :capture_log
  test "Service not available", context do
    use_cassette "error_service_not_available" do
      conn = get build_conn(), "/v2/onvif/v20/Display/GetServiceCapabilities?#{@access_params}&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      error_type = json_response(conn, 500) |> parse_onvif_error_type
      assert error_type == "ter:ActionNotSupported"
    end
  end

  @tag :capture_log
  test "bad parameter", context do
    use_cassette "error_bad_parameter" do
      conn = get build_conn(), "/v2/onvif/v20/Media/GetSnapshotUri?#{@access_params}&ProfileToken=Foo&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      error_type = json_response(conn, 500) |> parse_onvif_error_type
      assert error_type == "ter:InvalidArgVal"
    end
  end

  @tag :capture_log
  test "request timeout", context do
    use_cassette "error_request_timeout" do
      conn = get build_conn(), "/v2/onvif/v20/device_service/GetNetworkInterfaces?url=http://192.10.20.30:8100&auth=foo:bar&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      [timeout_message] = json_response(conn, 500)
      assert timeout_message == "req_timedout"
    end
  end

  @tag :capture_log
  test "bad url", context do
    use_cassette "error_bad_url" do
      conn = get build_conn(), "/v2/onvif/v20/device_service/GetNetworkInterfaces?url=abcde&auth=foo:bar&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      [_ , ["error", error]] = json_response(conn, 500)
      assert error == "nxdomain"
    end
  end
end
