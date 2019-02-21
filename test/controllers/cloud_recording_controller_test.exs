defmodule EvercamMedia.CloudRecordingControllerTest do
  use EvercamMediaWeb.ConnCase

  setup do
    country = Repo.insert!(%Country{name: "Something", iso3166_a2: "SMT"})
    user = Repo.insert!(%User{firstname: "John", lastname: "Doe", username: "johndoe", email: "john@doe.com", password: "password123", api_id: UUID.uuid4(:hex), api_key: UUID.uuid4(:hex), country_id: country.id})
    camera = Repo.insert!(%Camera{owner_id: user.id, name: "Austin", exid: "austin", is_public: false, config: %{ "external_host" => "202.83.28.14", "snapshots" => %{}}})
    cloud_recording = Repo.insert!(%CloudRecording{camera_id: camera.id, frequency: 2, storage_duration: 1, status: "on", schedule: []})

    params = %{
      camera_id: camera.id,
      frequency: "2",
      storage_duration: "1",
      status: "off",
      schedule: "{\"Monday\":[\"00:00-23:59\"],\"Tuesday\":[\"00:00-23:59\"]}"
    }

    {:ok, cloud_recordings: cloud_recording, user: user, camera: camera, params: params}
  end

  test "GET /v2/cameras/:id/apps/cloud-recording", context do
    camera_exid = "austin"
    response = build_conn() |> get("/v2/cameras/#{camera_exid}/apps/cloud-recording?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    response_body = %{"cloud_recordings" => [%{"frequency" => 2, "schedule" => [], "status" => "on", "storage_duration" => 1}]}
    assert response.status == 200
    assert Poison.decode!(response.resp_body) == response_body
  end

  test "GET /v2/cameras/:id/apps/cloud-recording Camera not found", context do
    camera_exid = "focuscam"
    response = build_conn() |> get("/v2/cameras/#{camera_exid}/apps/cloud-recording?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}")

    assert response.status == 404
    assert Poison.decode(response.resp_body) == {:ok, %{"message" => "Camera '#{camera_exid}' not found!"}}
  end

  test "POST /v2/cameras/:id/apps/cloud-recording when params valid.", context do
    response =
      build_conn()
      |> post("/v2/cameras/#{context[:camera].exid}/apps/cloud-recording?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", context[:params])

    response_body = %{"cloud_recordings" => [%{"frequency" => 2, "schedule" => %{"Monday" => ["00:00-23:59"], "Tuesday" => ["00:00-23:59"]}, "status" => "off", "storage_duration" => 1}]}
    assert Poison.decode!(response.resp_body) == response_body
  end

  test "POST /v2/cameras/:id/apps/cloud-recording when schedule isn't valid!", context do
    cr_params = Map.put(context[:params], :schedule, "1")
    response =
      build_conn()
      |> post("/v2/cameras/#{context[:camera].exid}/apps/cloud-recording?api_id=#{context[:user].api_id}&api_key=#{context[:user].api_key}", cr_params)

    assert Poison.decode!(response.resp_body) == %{"error" => "The parameter 'schedule' isn't valid."}
  end
end
