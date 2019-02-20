defmodule EvercamMedia.CameraStatusAutomation do
  import EvercamMediaWeb.CameraController, only: [check_params: 1]
  alias EvercamMedia.Util
  alias EvercamMedia.XMLParser
  alias EvercamMedia.HTTPClient
  alias Evercam.SnapshotRepo
  require Logger

  def check_camera_status(camera) do
    address = Camera.host(camera, "external")
    vh_port = Camera.port(camera, "external", "http")
    nvr_port = Camera.get_nvr_port(camera)

    case vh_port do
      port when port == nvr_port -> Logger.debug "Both ports same"
      _ ->
        vh_status = check_port_status(address, vh_port)
        nvr_status = check_port_status(address, nvr_port)
        do_action(camera, vh_status, nvr_status)
    end
  end

  defp do_action(camera, false, true) do
    Logger.debug "VH:Closed, NVR:Open"
    host = Camera.host(camera, "external")
    nvr_port = Camera.get_nvr_port(camera)
    username = Camera.username(camera)
    password = Camera.password(camera)

    get_vh_status(host, nvr_port, username, password)
    |> is_enabled(host, nvr_port, username, password, camera)
  end
  defp do_action(_camera, vh_port, nvr_port), do: Logger.debug "VH:Closed:#{vh_port}, NVR:Closed:#{nvr_port}"

  defp check_port_status(address, port) do
    params = %{"address" => address, "port" => port}
    case check_params(params) do
      {:invalid, message} ->
        Logger.error message
        false
      :ok ->
        Util.port_open?(address, port)
    end
  end

  defp get_vh_status(host, port, username, password) do
    url = "http://#{host}:#{port}/ISAPI/System/Network/extension"
    case HTTPClient.get(:digest_auth, url, username, password) do
      {:ok, %HTTPoison.Response{body: body}} ->
        body
        |> XMLParser.parse_inner_array
        |> XMLParser.parse_single_element('/networkExtension/enVirtualHost')
      {:error, %HTTPoison.Error{reason: reason}} ->
        Logger.error reason
        "false"
    end
  end

  defp enable_vh_port(host, port, username, password, camera) do
    xml = '<networkExtension xmlns="http://www.hikvision.com/ver20/XMLSchema" version="1.0"><enVirtualHost>true</enVirtualHost> </networkExtension>'
    post_url = "http://#{host}:#{port}/ISAPI/System/Network/extension"
    case HTTPClient.put(post_url, username, password, xml) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        insert_log(camera)
        body
      {_, %HTTPoison.Response{body: body}} -> Logger.error body
    end
  end

  def is_enabled("false", host, nvr_port, username, password, camera), do:  enable_vh_port(host, nvr_port, username, password, camera)
  def is_enabled(_, _host, _nvr_port, _username, _password, _), do:  Logger.debug "Does not enable VH status"

  defp insert_log(camera) do
    parameters = %{camera_id: camera.id, camera_exid: camera.exid, action: "vh status", done_at: Calendar.DateTime.now_utc}
    changeset = CameraActivity.changeset(%CameraActivity{}, parameters)
    SnapshotRepo.insert(changeset)
  end
end
