defmodule EvercamMedia.CameraShareRequestControllerTest do
  use EvercamMediaWeb.ConnCase

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "PK"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", country_id: country.id, api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex)})
    camera = Repo.insert!(%Camera{owner_id: user.id, name: "Austin", exid: "austin", is_public: false, config: ""})
    _share_request = Repo.insert!(%CameraShareRequest{camera_id: camera.id, user_id: user.id, key: UUID.uuid4(:hex), email: "abc@email.com", status: -1, rights: "list,snapshot"})

    {:ok, user: user, camera: camera}
  end

  test "GET /v2/cameras/:id/shares/requests, with valid params", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/shares/requests?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    share_requests =
      response.resp_body
      |> Jason.decode!
      |> Map.get("share_requests")
      |> List.first

    assert response.status() == 200
    assert Map.get(share_requests, "camera_id") == context[:camera].exid
  end

  test "GET /v2/cameras/:id/shares/requests, when camera does not exist", context do
    response =
      build_conn()
      |> get("/v2/cameras/austinxyz/shares/requests?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Jason.decode!(response.resp_body)["message"] == "The austinxyz camera does not exist."
  end

  test "GET /v2/cameras/:id/shares/requests, when required keys are missing" do
    response =
      build_conn()
      |> get("/v2/cameras/austin/shares/requests")

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["message"] == "Unauthorized."
  end

  test "DELETE /v2/cameras/:id/shares/requests, with valid params", context do
    response =
      build_conn()
      |> delete("/v2/cameras/austin/shares/requests?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", %{email: "abc@email.com"})

    assert response.status() == 200
    assert Jason.decode!(response.resp_body) == %{}
  end

  test "DELETE /v2/cameras/:id/shares/requests, when required keys are missing" do
    response =
      build_conn()
      |> delete("/v2/cameras/austin/shares/requests", %{email: "abc@email.com"})

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["message"] == "Unauthorized."
  end

  test "DELETE /v2/cameras/:id/shares/requests, when share request not found", context do
    response =
      build_conn()
      |> delete("/v2/cameras/austin/shares/requests?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", %{email: "xyz@email.com"})

    assert response.status() == 404
    assert Jason.decode!(response.resp_body)["message"] == "Share request not found."
  end

  test "PATCH /v2/cameras/:id/shares/requests, with valid params", context do
    params = %{
      email: "abc@email.com",
      rights: "snapshot,list"
    }
    response =
      build_conn()
      |> patch("/v2/cameras/austin/shares/requests?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    share_requests =
      response.resp_body
      |> Jason.decode!
      |> Map.get("share_requests")
      |> List.first

    assert response.status() == 200
    assert Map.get(share_requests, "email") == params[:email]
    assert Map.get(share_requests, "rights") == params[:rights]
  end

  test "PATCH /v2/cameras/:id/shares/requests, when required keys are missing" do
    response =
      build_conn()
      |> patch("/v2/cameras/austin/shares/requests", %{email: "abc@email.com", rights: "snapshot,list"})

    assert response.status == 401
    assert Jason.decode!(response.resp_body)["message"] == "Unauthorized."
  end

  test "PATCH /v2/cameras/:id/shares/requests, when invalid rights", context do
    params = %{
      email: "abc@email.com",
      rights: "zxcv,list"
    }

    response =
      build_conn()
      |> patch("/v2/cameras/austin/shares/requests?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    message =
      response.resp_body
      |> Jason.decode!
      |> Map.get("message")
      |> Map.get("rights")

    assert response.status() == 400
    assert message == ["Invalid rights specified in request."]
  end

  test "PATCH /v2/cameras/:id/shares/requests, when share request not found", context do
    params = %{
      email: "xyz@email.com",
      rights: "snapshot,list"
    }

    response =
      build_conn()
      |> patch("/v2/cameras/austin/shares/requests?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    assert response.status() == 404
    assert Jason.decode!(response.resp_body)["message"] == "Share request not found."
  end
end
