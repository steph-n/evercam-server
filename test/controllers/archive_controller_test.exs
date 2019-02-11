defmodule EvercamMedia.ArchiveControllerTest do
  use EvercamMediaWeb.ConnCase

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex), country_id: country.id})
    camera = Repo.insert!(%Camera{owner_id: user.id, name: "Austin", exid: "austin", is_public: false, config: %{ "external_host" => "202.83.28.14", "snapshots" => %{}}})
    archive = Repo.insert!(%Archive{camera_id: camera.id, title: "dexter", requested_by: user.id, from_date: Calendar.DateTime.now_utc, to_date: Calendar.DateTime.now_utc, exid: "dexi-test", status: 0})

    params = %{
      title: "Testing",
      public: "truthy",
      camera_id: camera.id,
      requested_by: "#{user.username}",
      from_date: "1475751645",
      to_date: "1475753445",
      status: 0,
      type: "clip"
    }

    {:ok, user: user, camera: camera, archive: archive, params: params}
  end

  test "GET /v1/cameras/:id/archives Camera not found", context do
    camera_exid = "focuscam"
    response = build_conn() |> get("/v1/cameras/#{camera_exid}/archives?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode(response.resp_body) == {:ok, %{"message" => "Camera '#{camera_exid}' not found!"}}
  end

  test "GET /v1/cameras/:id/archives/:archive_id archive not found", context do
    archive_id = "text-dexter"
    response = build_conn() |> get("/v1/cameras/#{context[:camera].exid}/archives/#{archive_id}?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode(response.resp_body) == {:ok, %{"message" => "Archive 'text-dexter' not found!"}}
  end

  test "POST /v1/cameras/:id/archives when params aren't valid!", context do
    response =
      build_conn()
      |> post("/v1/cameras/#{context[:camera].exid}/archives?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", context[:params])

    assert response.status == 400
    assert Poison.decode(response.resp_body) == {:ok, %{"message" => %{"public" => ["is invalid"]}}}
  end

  test "POST /v1/cameras/:id/archives when params are valid!", context do
    params = Map.merge(context[:params], %{public: "false"})
    response =
      build_conn()
      |> post("/v1/cameras/#{context[:camera].exid}/archives?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    assert response.status == 201
  end

  test "POST /v1/cameras/:id/archives when clip duration greater than 60 minutes", context do
    params = Map.merge(context[:params], %{public: "false", to_date: "1475755545", type: "clip"})
    response =
      build_conn()
      |> post("/v1/cameras/#{context[:camera].exid}/archives?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    error_message =
      response.resp_body
      |> Poison.decode
      |> elem(1)
      |> Map.get("message")

    assert response.status == 400
    assert error_message == "Clip duration cannot be greater than 60 minutes."
  end
end
