defmodule EvercamMedia.CompareControllerTest do
  use EvercamMediaWeb.ConnCase

  setup do
    System.put_env("SNAP_KEY", "aaaaaaaaaaaaaaaa")
    System.put_env("SNAP_IV", "bbbbbbbbbbbbbbbb")

    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", country_id: country.id, api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex)})
    _access_token1 = Repo.insert!(%AccessToken{user_id: user.id, request: UUID.uuid4(:hex), is_revoked: false})
    camera = Repo.insert!(%Camera{owner_id: user.id, name: "Austin", exid: "austin", is_public: false, config: %{"external_host" => "192.168.1.100", "external_http_port" => "80"}})
    compare = Repo.insert!(%Compare{camera_id: camera.id, name: "Test Compare", exid: "compar-gstd", before_date: Calendar.DateTime.now_utc, after_date: Calendar.DateTime.now_utc, public: false, embed_code: "<div></div>", requested_by: user.id})

    {:ok, user: user, camera: camera, compare: compare}
  end

  test "GET /v2/cameras/:id/compares, when passed camera_id not exist", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin1/compares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode!(response.resp_body)["message"] == "Camera 'austin1' not found!"
  end

  test "GET /v2/cameras/:id/compares, when passed invalid keys", _context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/compares")

    assert response.status == 401
    assert Poison.decode!(response.resp_body)["message"] == "Unauthorized."
  end

  test "GET /v2/cameras/:id/compares, with valid params", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/compares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    _compares =
      response.resp_body
      |> Poison.decode!
      |> Map.get("compares")
      |> List.first

    assert response.status() == 200
  end

  test "GET /v2/cameras/:id/compares/:compare_id, when passed camera_id not exist", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin1/compares/compar-gstd?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode!(response.resp_body)["message"] == "Camera 'austin1' not found!"
  end

  test "GET /v2/cameras/:id/compares/:compare_id, when passed compare_id not exist", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/compares/compar-gstd1?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode!(response.resp_body)["message"] == "Compare archive 'compar-gstd1' not found!"
  end

  test "GET /v2/cameras/:id/compares/:compare_id, when passed invalid keys", _context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/compares/compar-gstd")

    assert response.status == 403
    assert Poison.decode!(response.resp_body)["message"] == "Forbidden."
  end

  test "GET /v2/cameras/:id/compares/:compare_id, with valid params", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/compares/compar-gstd?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    compares =
      response.resp_body
      |> Poison.decode!
      |> Map.get("compares")
      |> List.first

    assert response.status() == 200
    assert compares["id"] == "compar-gstd"
  end

  test "POST /v2/cameras/:id/compares, when invalid or nil api keys", _context do
    timestamp = Calendar.DateTime.now!("UTC") |> Calendar.DateTime.Format.unix
    params = %{
      name: "New Compare",
      before_date: "#{timestamp}",
      after_date: "#{timestamp}",
      embed: "<div></div>"
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin/compares", params)

    assert response.status == 401
    assert Poison.decode!(response.resp_body)["message"] == "Unauthorized."
  end

  test "POST /v2/cameras/:id/compares, when passed camera_id not exist", context do
    timestamp = Calendar.DateTime.now!("UTC") |> Calendar.DateTime.Format.unix
    params = %{
      name: "New Compare",
      before_date: "#{timestamp}",
      after_date: "#{timestamp}",
      embed: "<div></div>"
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin1/compares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    assert response.status == 404
    assert Poison.decode!(response.resp_body)["message"] == "Camera 'austin1' not found!"
  end

  test "POST /v2/cameras/:id/compares, invalid params", context do
    timestamp = Calendar.DateTime.now!("UTC") |> Calendar.DateTime.Format.unix
    params = %{
      name: "New Compare",
      before_date: "#{timestamp}"
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin/compares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    assert response.status == 400
  end

  test "POST /v2/cameras/:id/compares, valid params", context do
    timestamp = Calendar.DateTime.now!("UTC") |> Calendar.DateTime.Format.unix
    params = %{
      name: "New Compare",
      before_date: "#{timestamp}",
      after_date: "#{timestamp}",
      before_image: "data:image/jpeg;base64,jkhdsifuhsduhfdsf",
      after_image: "data:image/jpeg;base64,jkhdsifuhsduhfdsf",
      embed: "<div></div>",
      exid: "testing-compare",
      requested_by: context[:user].id
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin/compares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    compare =
      response.resp_body
      |> Poison.decode!
      |> Map.get("compares")
      |> List.first

    assert response.status == 201
    assert compare["title"] == "New Compare"
  end
end
