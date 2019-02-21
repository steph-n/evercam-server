defmodule EvercamMedia.CameraShareControllerTest do
  use EvercamMediaWeb.ConnCase

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "PK"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", country_id: country.id, api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex)})
    user2 = Repo.insert!(%User{firstname: "Smith", lastname: "Marc", username: "smithmarc", email: "smith@dmarc.com", password: "password456", country_id: country.id, api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex)})
    user3 = Repo.insert!(%User{firstname: "ABC", lastname: "XYZ", username: "abcxyz", email: "abc@xyz.com", password: "password456", country_id: country.id})
    _access_token1 = Repo.insert!(%AccessToken{user_id: user3.id, request: UUID.uuid4(:hex), is_revoked: false})
    _access_token2 = Repo.insert!(%AccessToken{user_id: user2.id, request: UUID.uuid4(:hex), is_revoked: false})
    camera = Repo.insert!(%Camera{owner_id: user.id, name: "Austin", exid: "austin", is_public: false, config: ""})
    remembrance_camera = Repo.insert!(%Camera{owner_id: user.id, name: "Herbst Wicklow Cam", exid: "evercam-remembrance-camera", is_public: false, config: ""})
    share = Repo.insert!(%CameraShare{camera_id: camera.id, user_id: user2.id, sharer_id: user.id, kind: "private"})
    _share2 = Repo.insert!(%CameraShare{camera_id: remembrance_camera.id, user_id: user2.id, sharer_id: user.id, kind: "private"})
    _share_request = Repo.insert!(%CameraShareRequest{camera_id: camera.id, user_id: user.id, email: "share_request@xyz.com", status: -1, rights: "snapshot,list", key: UUID.uuid4(:hex)})

    {:ok, user: user, camera: camera, share: share}
  end

  test "GET /v2/cameras/:id/shares, with valid params", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    shares =
      response.resp_body
      |> Poison.decode!
      |> Map.get("shares")
      |> List.first

    assert response.status() == 200
    assert shares["camera_id"] == context[:camera].exid
  end

  test "GET /v2/cameras/:id/shares, when passed user_id not exist", context do
    response =
      build_conn()
      |> get("/v2/cameras/austin/shares?user_id=johndoexyz&api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode!(response.resp_body)["message"] == "User 'johndoexyz' does not exist."
  end

  test "GET /v2/cameras/:id/shares, when camera does not exist", context do
    response =
      build_conn()
      |> get("/v2/cameras/austinxyz/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode!(response.resp_body)["message"] == "The austinxyz camera does not exist."
  end

  test "GET /v2/cameras/:id/shares, when required keys are missing" do
    response =
      build_conn()
      |> get("/v2/cameras/austin/shares")

    assert response.status == 200
    assert Poison.decode!(response.resp_body)["shares"] == []
  end

  test "POST /v2/cameras/:id/shares, return share when sharee exists", context do
    params = %{
      email: ["abcxyz"],
      rights: "snapshot,list"
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    share =
      response.resp_body
      |> Poison.decode!
      |> Map.get("shares")
      |> List.first

    assert response.status == 201
    assert Map.get(share, "camera_id") == context[:camera].exid
    assert Map.get(share, "sharer_id") == context[:user].username
  end

  test "POST /v2/cameras/:id/shares, return share request when sharee not exists", context do
    params = %{
      email: ["user@new.com"],
      rights: "snapshot,list"
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    share =
      response.resp_body
      |> Poison.decode!
      |> Map.get("share_requests")
      |> List.first

    [email] = params[:email]
    assert response.status == 201
    assert Map.get(share, "camera_id") == context[:camera].exid
    assert Map.get(share, "email") == email
  end

  test "POST /v2/cameras/:id/shares, camera already shared", context do
    params = %{
      email: ["smithmarc"],
      rights: "snapshot,list"
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("errors")
      |> List.first
      |> Map.get("text")

    assert message == "The camera has already been shared with this user. (#{params[:email]})"
  end

  test "POST /v2/cameras/:id/shares, share request already exists", context do
    params = %{
      email: ["share_request@xyz.com"],
      rights: "snapshot,list"
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("errors")
      |> List.first
      |> Map.get("text")

    assert message == "A share request already exists for the '#{params[:email]}' email address for this camera. (#{params[:email]})"
  end

  test "POST /v2/cameras/:id/shares, invalid rights", context do
    params = %{
      email: ["abcxyz"],
      rights: "abc,list"
    }
    response =
      build_conn()
      |> post("/v2/cameras/austin/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("errors")
      |> List.first
      |> Map.get("text")

    assert message == "Invalid rights specified in request. (#{params[:email]})"
  end

  test "PATCH /v2/cameras/:id/shares, return share when valid params", context do
    params = %{
      email: "smithmarc",
      rights: "snapshot,list,view,edit"
    }
    response =
      build_conn()
      |> patch("/v2/cameras/austin/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    share =
      response.resp_body
      |> Poison.decode!
      |> Map.get("shares")
      |> List.first

    assert response.status == 200
    assert Map.get(share, "camera_id") == context[:camera].exid
    assert Map.get(share, "sharer_id") == context[:user].username
  end

  test "PATCH /v2/cameras/:id/shares, when camera not exists.", context do
    params = %{
      email: "smithmarc",
      rights: "snapshot,list"
    }
    response =
      build_conn()
      |> patch("/v2/cameras/austin1/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")

    assert response.status == 404
    assert message == "The austin1 camera does not exist."
  end

  test "PATCH /v2/cameras/:id/shares, when invalid rights.", context do
    params = %{
      email: "smithmarc",
      rights: "snapshot,list,test"
    }
    response =
      build_conn()
      |> patch("/v2/cameras/austin/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", params)

    message =
      response.resp_body
      |> Poison.decode!
      |> Map.get("message")
      |> Map.get("rights")

    assert response.status == 400
    assert message == ["Invalid rights specified in request."]
  end

  test "DELETE /v2/cameras/:id/shares, when valid params", context do
    response =
      build_conn()
      |> delete("/v2/cameras/austin/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", %{email: "smithmarc"})

    assert response.status == 200
    assert response.resp_body == "{}"
  end

  test "DELETE /v2/cameras/:id/shares, when share not found", context do
    response =
      build_conn()
      |> delete("/v2/cameras/austin/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", %{email: "smithmarc1"})

    assert response.status == 404
    assert Poison.decode!(response.resp_body)["message"] == "Sharee 'smithmarc1' not found."
  end

  test "DELETE /v2/cameras/:id/shares, when required permission", _context do
    response =
      build_conn()
      |> delete("/v2/cameras/austin/shares", %{email: "smithmarc"})

    assert response.status == 401
    assert Poison.decode!(response.resp_body)["message"] == "Unauthorized."
  end

  test "GET /v/cameras/evercam-remembrance-camera/shares, return empty array when exid is evercam-remembrance-camera", context do
    response =
      build_conn()
      |> get("/v2/cameras/evercam-remembrance-camera/shares?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    shares =
      response.resp_body
      |> Poison.decode!
      |> Map.get("shares")

    assert shares == []
    assert response.status == 200
  end
end
