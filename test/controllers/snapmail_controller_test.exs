defmodule EvercamMedia.SnapmailControllerTest do
  use EvercamMediaWeb.ConnCase

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", country_id: country.id, api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex)})
    camera = Repo.insert!(%Camera{owner_id: user.id, name: "Austin", exid: "austin", is_public: false, config: %{"external_host" => "192.168.1.100", "external_http_port" => "80"}})
    snapmail = Repo.insert!(%Snapmail{subject: "test snapmail", notify_time: "16:00", exid: "test-spmail", user_id: user.id, recipients: "test@test.com", timezone: "Europe/Dublin", notify_days: "Monday", is_paused: false, is_public: true})
    _snapmail_camera = Repo.insert!(%SnapmailCamera{snapmail_id: snapmail.id, camera_id: camera.id})

    {:ok, user: user, camera: camera, snapmail: snapmail}
  end

  test "GET /v2/snapmails, all snapmails created", context do
    response =
      build_conn()
      |> get("/v2/snapmails?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}&camera_id=#{context[:camera].exid}")

    assert response.status == 200
  end

  test "UPDATE /v2/snapmails/snapmail_id", context do
    updated_params = %{
      timezone: "Etc/UTC",
      notify_days: "Monday,Friday"
    }
    response =
      build_conn()
      |> patch("/v2/snapmails/#{context[:snapmail].exid}?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", updated_params)

    assert Poison.decode!(response.resp_body)["snapmails"] |> List.first |> Map.get("timezone") == "Etc/UTC"
    assert Poison.decode!(response.resp_body)["snapmails"] |> List.first |> Map.get("notify_days") == "Monday,Friday"
    assert response.status == 200
  end

  test "GET /v2/snapmails/snapmail_id when snapmail doesn't exist", context do
    response =
      build_conn()
      |> get("/v2/snapmails/test_snapmail?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode!(response.resp_body)["message"] == "Snapmail not found."
  end

  test "DELETE /v2/snapmails, delete a snapmail", context do
    response =
      build_conn()
      |> delete("/v2/snapmails/#{context[:snapmail].exid}?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 200
    assert Poison.decode!(response.resp_body) == %{}
  end

  test "UPDATE /v2/snapmails, when notify_time is invalid", context do
    updated_params = %{
      notify_time: "ett",
    }
    response =
      build_conn()
      |> patch("/v2/snapmails/#{context[:snapmail].exid}?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", updated_params)

    assert Poison.decode!(response.resp_body)["message"] |> Map.get("notify_time") == ["Notify time is invalid"]
    assert response.status == 400
  end

  test "GET /v2/snapmails, when api credentials are wrong", _context do
    response =
      build_conn()
      |> get("/v2/snapmails")

    assert response.status == 401
    assert Poison.decode!(response.resp_body)["message"] == "Unauthorized."
  end

  test "POST /v2/snapmails, valid params", context do
    params = %{
      camera_exids: "#{context[:camera].exid}",
      recipients: "john@doe.com",
      notify_days: "Friday",
      notify_time: "16:00",
      timezone: "Etc/UTC",
      subject: "Test Snapmail"
    }
    response =
      build_conn()
      |> post("/v2/snapmails?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    timelapse =
      response.resp_body
      |> Poison.decode!
      |> Map.get("snapmails")
      |> List.first

    assert response.status == 201
    assert timelapse["title"] == "Test Snapmail"
  end
end
