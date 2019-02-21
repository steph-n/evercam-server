defmodule EvercamMedia.ONVIFPTZControllerTest do
  use EvercamMediaWeb.ConnCase
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney, options: [clear_mock: true]

  @moduletag :onvif

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex), country_id: country.id})

    {:ok, user: user}
  end

  test "GET /v2/cameras/:id/ptz/presets, gives something", context do
    use_cassette "ptz_presets" do
      conn = get build_conn(), "/v2/cameras/recorded-response/ptz/presets?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      presets = conn |> json_response(200) |> Map.get("Presets")
      assert presets != nil
    end
  end

  @tag :capture_log
  test "GET /v2/cameras/:id/ptz/presets, when error, returns empty set", context do
    use_cassette "ptz_presets_with_error" do
      conn = get build_conn(), "/v2/cameras/recorded-response/ptz/presets?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      presets = conn |> json_response(200) |> Map.get("Presets")
      assert presets == []
    end
  end

  test "GET /v2/cameras/:id/ptz/status, gives something", context do
    use_cassette "ptz_status" do
      conn = get build_conn(), "/v2/cameras/recorded-response/ptz/status?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
      error_status = conn |> json_response(200) |> Map.get("PTZStatus") |> Map.get("Error")
      assert error_status == "NO error"
    end
  end
end
