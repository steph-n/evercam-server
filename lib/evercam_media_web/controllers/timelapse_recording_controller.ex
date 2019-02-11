defmodule EvercamMediaWeb.TimelapseRecordingController do
  use EvercamMediaWeb, :controller
  alias EvercamMediaWeb.ErrorView
  alias EvercamMediaWeb.TimelapsedRecordingView
  alias EvercamMedia.TimelapseRecording.TimelapseRecordingSupervisor
  import EvercamMedia.Validation.CloudRecording

  def show(conn, %{"id" => exid}) do
    current_user = conn.assigns[:current_user]
    camera = Camera.by_exid_with_associations(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_edit(current_user, camera, conn),
         do: camera.timelapse_recordings |> render_timelapse_recording(conn)
  end

  def create(conn, %{"id" => exid} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.by_exid_with_associations(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_edit(current_user, camera, conn),
         :ok <- validate_params(params) |> ensure_params(conn)
    do
      params = %{
        camera_id: camera.id,
        frequency: params["frequency"],
        storage_duration: params["storage_duration"],
        status: params["status"],
        schedule: get_json(params["schedule"])
      }

      old_timelapse_recordings = camera.timelapse_recordings || %TimelapseRecording{}
      action_log = get_action_log(camera.timelapse_recordings)
      case old_timelapse_recordings |> TimelapseRecording.changeset(params) |> Repo.insert_or_update do
        {:ok, timelapse_recording} ->
          camera = camera |> Repo.preload(:timelapse_recordings, force: true)
          Camera.invalidate_camera(camera)
          "timelapse_#{exid}"
          |> String.to_atom
          |> Process.whereis
          |> start_or_update_worker(camera)

          CameraActivity.log_activity(current_user, camera, "timelapse recordings #{action_log}",
            %{
              ip: user_request_ip(conn, params["requester_ip"]),
              tr_settings: %{
                old: set_settings(old_timelapse_recordings),
                new: set_settings(timelapse_recording)
                },
              }
          )
          conn
          |> put_view(TimelapsedRecordingView)
          |> render("timelapse_recording.json", %{timelapse_recording: timelapse_recording})
        {:error, changeset} ->
          render_error(conn, 400, changeset)
      end
    end
  end

  def start_or_update_worker(nil, camera), do: TimelapseRecordingSupervisor.start_worker(camera)
  def start_or_update_worker(worker, camera) do
    TimelapseRecordingSupervisor.update_worker(worker, camera)
  end

  defp set_settings(timelapse_recording) do
    case timelapse_recording.camera_id do
      nil -> nil
      _ ->
        %{status: timelapse_recording.status, storage_duration: timelapse_recording.storage_duration, frequency: timelapse_recording.frequency, schedule: timelapse_recording.schedule}
    end
  end

  defp ensure_camera_exists(nil, exid, conn) do
    conn
    |> put_status(404)
    |> render(ErrorView, "error.json", %{message: "Camera '#{exid}' not found!"})
  end
  defp ensure_camera_exists(_camera, _id, _conn), do: :ok

  defp ensure_can_edit(current_user, camera, conn) do
    if Permission.Camera.can_edit?(current_user, camera) do
      :ok
    else
      conn
      |> put_status(403)
      |> render(ErrorView, "error.json", %{message: "You don't have sufficient rights for this."})
    end
  end

  defp ensure_params(:ok, _conn), do: :ok
  defp ensure_params({:invalid, message}, conn), do: json(conn, %{error: message})

  defp get_json(schedule) do
    case Poison.decode(schedule) do
      {:ok, json} -> json
    end
  end

  defp render_timelapse_recording(nil, conn), do: conn |> put_view(TimelapsedRecordingView) |> render("show.json", %{timelapse_recording: []})
  defp render_timelapse_recording(tr, conn), do: conn |> put_view(TimelapsedRecordingView) |> render("timelapse_recording.json", %{timelapse_recording: tr})

  defp get_action_log(nil), do: "created"
  defp get_action_log(_cloud_recording), do: "updated"
end
