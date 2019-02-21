defmodule EvercamMedia.TimelapseControllerTest do
  use EvercamMediaWeb.ConnCase

  setup do
    System.put_env("SNAP_KEY", "aaaaaaaaaaaaaaaa")
    System.put_env("SNAP_IV", "bbbbbbbbbbbbbbbb")

    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", country_id: country.id, api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex)})
    camera = Repo.insert!(%Camera{owner_id: user.id, name: "Austin", exid: "austin", is_public: false, config: %{"external_host" => "192.168.1.100", "external_http_port" => "80"}})
    timelapse = Repo.insert!(%Timelapse{camera_id: camera.id, exid: "timel-exid", user_id: user.id, title: "Timelapse Title", frequency: 1, status: 0, date_always: true, time_always: true})

    {:ok, user: user, camera: camera, timelapse: timelapse}
  end

  test "GET /cameras/:id/timelapses, when passed camera_id not exist", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin1/timelapses?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 403
    assert Poison.decode!(response.resp_body)["message"] == "Forbidden."
  end

  test "GET /v2/cameras/:id/timelapses, when passed invalid keys", _context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/timelapses")

    assert response.status == 401
    assert Poison.decode!(response.resp_body)["message"] == "Unauthorized."
  end

  test "GET /v2/cameras/:id/timelapses, with valid params", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/timelapses?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    _timelapses =
      response.resp_body
      |> Poison.decode!
      |> Map.get("timelapses")
      |> List.first

    assert response.status() == 200
  end

  test "GET /v2/timelapses, when passed invalid keys", _context do
    response =
      build_conn()
      |> get("/v2/timelapses")

    assert response.status == 401
    assert Poison.decode!(response.resp_body)["message"] == "Unauthorized."
  end

  test "GET /v2/timelapses, with valid params", context do
    response =
      build_conn()
      |> get("/v2/timelapses?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    _timelapses =
      response.resp_body
      |> Poison.decode!
      |> Map.get("timelapses")
      |> List.first

    assert response.status() == 200
  end

  test "GET /cameras/:id/timelapses/:timelapse_id, when user do not have permission", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin1/timelapses/timel-exid?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 403
    assert Poison.decode!(response.resp_body)["message"] == "Forbidden."
  end

  test "GET /cameras/:id/timelapses/:timelapse_id, when passed camera_id not exist", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/timelapses/timel-exid1?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode!(response.resp_body)["message"] == "Timelapse not found."
  end

  test "GET /cameras/:id/timelapses/:timelapse_id, with valid params", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/timelapses/timel-exid?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    timelapse =
      response.resp_body
      |> Poison.decode!
      |> Map.get("timelapses")
      |> List.first

    assert response.status == 200
    assert timelapse["id"] == "timel-exid"
  end

  test "POST /v2/cameras/:id/timelapses, when user do not have permission", _context do
    params = %{
      title: "New Timelapse"
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin/timelapses", params)

    assert response.status == 403
    assert Poison.decode!(response.resp_body)["message"] == "Forbidden."
  end

  test "POST /v2/cameras/:id/timelapses, invalid params", context do
    params = %{
      title: "Timelapse 1st"
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin/timelapses?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    assert response.status == 400
  end

  test "POST /v2/cameras/:id/timelapses, valid params", context do
    params = %{
      title: "New Timelapse",
      frequency: 1,
      status: 0,
      date_always: "true",
      time_always: "true"
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin/timelapses?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    timelapse =
      response.resp_body
      |> Poison.decode!
      |> Map.get("timelapses")
      |> List.first

    assert response.status == 201
    assert timelapse["title"] == "New Timelapse"
  end

  test "PATCH /v2/cameras/:id/timelapses/:timelapse_id, when user do not have permission", _context do
    params = %{
      title: "New Timelapse"
    }
    response =
      build_conn()
      |> patch("/v2/cameras/austin/timelapses/timel-exid", params)

    assert response.status == 403
    assert Poison.decode!(response.resp_body)["message"] == "Forbidden."
  end

  test "PATCH /v2/cameras/:id/timelapses/:timelapse_id, when timelapse not exist", context do
    params = %{
      title: "Timelapse 1st"
    }
    response =
      build_conn()
      |> patch("/v2/cameras/austin/timelapses/timel-exid1?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    assert response.status == 404
    assert Poison.decode!(response.resp_body)["message"] == "Timelapse not found."
  end

  test "PATCH /v2/cameras/:id/timelapses/:timelapse_id, valid params", context do
    params = %{
      title: "Change Timelapse Title"
    }
    response =
      build_conn()
      |> patch("/v2/cameras/austin/timelapses/timel-exid?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    timelapse =
      response.resp_body
      |> Poison.decode!
      |> Map.get("timelapses")
      |> List.first

    assert response.status == 200
    assert timelapse["title"] == "Change Timelapse Title"
  end

  test "DELETE /v2/cameras/:id/timelapses/:timelapse_id, when user do not have permission", _context do
    response =
      build_conn()
      |> delete("/v2/cameras/austin/timelapses/timel-exid")

    assert response.status == 403
    assert Poison.decode!(response.resp_body)["message"] == "Forbidden."
  end

  test "DELETE /v2/cameras/:id/timelapses/:timelapse_id, when timelapse not exist", context do
    response =
      build_conn()
      |> delete("/v2/cameras/austin/timelapses/timel-exid1?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode!(response.resp_body)["message"] == "Timelapse not found."
  end

  test "DELETE /v2/cameras/:id/timelapses/:timelapse_id, valid params", context do
    response =
      build_conn()
      |> delete("/v2/cameras/austin/timelapses/timel-exid?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")


    assert response.status == 200
    assert Poison.decode!(response.resp_body) == %{}
  end
end
