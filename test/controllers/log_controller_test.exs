defmodule EvercamMedia.LogControllerTest do
  use EvercamMediaWeb.ConnCase

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex), country_id: country.id})
    camera = Repo.insert!(%Camera{owner_id: user.id, name: "Austin", exid: "austin", is_public: false, config: %{ "external_host" => "202.83.28.14", "snapshots" => %{}}})

    params = %{
      id: camera.exid,
      from: "2019-01-05T08:00:00.000Z",
      to: "2019-02-05T08:00:00.000Z",
      page: "1",
      limit: "4"
    }

    {:ok, user: user, camera: camera, params: params}
  end

  test "GET /v2/cameras/:id/logs Camera not found", context do
    camera_exid = "focuscam"
    response = build_conn() |> get("/v2/cameras/#{camera_exid}/logs?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode(response.resp_body) == {:ok, %{"message" => "Camera '#{camera_exid}' not found!"}}
  end

  test "GET /v2/cameras/:id/logs Unauthorized" do
    camera_exid = "austin"
    response = build_conn() |> get("/v2/cameras/#{camera_exid}/logs?")

    assert response.status == 401
    assert Poison.decode(response.resp_body) == {:ok, %{"message" => "Unauthorized."}}
  end

  test "GET /v2/cameras/:id/logs when params are valid!", context do
    response =
      build_conn()
      |> get("/v2/cameras/#{context[:camera].exid}/logs?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", context[:params])

    response_body = %{"camera_exid" => "austin", "camera_name" => "Austin", "logs" => [], "pages" => 0.0}
    assert response.status == 200
    assert Poison.decode(response.resp_body) == {:ok, response_body}
  end

  test "GET /v2/cameras/:id/logs when from is greater than to!", context do
    params = Map.merge(context[:params], %{from: "1464918180", to: "1464831780"})
    response =
      build_conn()
      |> get("/v2/cameras/#{context[:camera].exid}/logs?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)
    assert response.status == 400
    assert Poison.decode(response.resp_body) == {:ok, %{"message" => "From can't be higher than to."}}
  end
end
