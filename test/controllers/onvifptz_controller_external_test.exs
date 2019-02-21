defmodule EvercamMedia.ONVIFPTZControllerExternalTest do
  use EvercamMediaWeb.ConnCase

  @moduletag :onvif
  @moduletag :external

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex), country_id: country.id})

    {:ok, user: user}
  end

  test "POST /v2/cameras/:id/ptz/relative?left=0&right=10&up=0&down=10&zoom=0 moves right and down", context do
    # get home first
    conn = post build_conn(), "/v2/cameras/mobile-mast-test/ptz/home?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
    assert json_response(conn, 201) == "ok"
    # give time to the camera to move
    :timer.sleep(3000)
    conn = get build_conn(), "/v2/cameras/mobile-mast-test/ptz/status?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
    response = json_response(conn, 200)
    x_before = extract_position(response, "x")
    y_before = extract_position(response, "y")
    conn = post(
      build_conn(),
      "/v2/cameras/mobile-mast-test/ptz/relative?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}",
      %{"left" => "0", "right" => "10", "up" => "0", "down" => "10", "zoom" => "0"}
    )
    assert json_response(conn, 201) == "ok"
    # give time to the camera to move
    :timer.sleep(3000)
    conn = get build_conn(), "/v2/cameras/mobile-mast-test/ptz/status?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
    response = json_response(conn, 200)
    x_after = extract_position(response, "x")
    y_after = extract_position(response, "y")
    assert (x_after - x_before) * 100 |> round == 10
    assert (y_after - y_before) * 100 |> round == -20
  end

  test "POST /v2/cameras/:id/ptz/relative?left=10&right=0&up=10&down=0&zoom=0 moves left and up", context do
    # get home first
    conn = post build_conn(), "/v2/cameras/mobile-mast-test/ptz/home?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
    assert json_response(conn, 201) == "ok"
    # give time to the camera to move
    :timer.sleep(3000)
    conn = get build_conn(), "/v2/cameras/mobile-mast-test/ptz/status?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
    response = json_response(conn, 200)
    x_before = extract_position(response, "x")
    y_before = extract_position(response, "y")
    conn = post(
      build_conn(),
      "/v2/cameras/mobile-mast-test/ptz/relative?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}",
      %{"left" => "10", "right" => "0", "up" => "10", "down" => "0", "zoom" => "0"}
    )
    assert json_response(conn, 201) == "ok"
    # give time to the camera to move
    :timer.sleep(3000)
    conn = get build_conn(), "/v2/cameras/mobile-mast-test/ptz/status?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}"
    response = json_response(conn, 200)
    x_after = extract_position(response, "x")
    y_after = extract_position(response, "y")
    assert x_before == -1.0
    assert x_after == 0.9
    assert (y_after - y_before) * 100 |> round == 20
  end

  defp extract_position(map, coord) do
    map
    |> Map.get("PTZStatus")
    |> Map.get("Position")
    |> Map.get("PanTilt")
    |> Map.get(coord)
    |> String.to_float
  end
end
