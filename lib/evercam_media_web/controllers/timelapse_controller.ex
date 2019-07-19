defmodule EvercamMediaWeb.TimelapseController do
  use EvercamMediaWeb, :controller
  alias EvercamMedia.Timelapse.TimelapserSupervisor

  def user_all(conn, _params) do
    caller = conn.assigns[:current_user]

    with :ok <- authorized(conn, caller)
    do
      timelapses = Timelapse.by_user_id(caller.id)
      render(conn, "index.json", %{timelapses: timelapses})
    end
  end

  def all(conn, %{"id" => exid}) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- authorized(conn, caller),
         :ok <- user_can_list(conn, caller, camera)
    do
      timelapses = Timelapse.by_camera_id(camera.id)
      render(conn, "index.json", %{timelapses: timelapses})
    end
  end

  def show(conn, %{"id" => camera_exid, "timelapse_id" => timelapse_exid}) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(camera_exid)

    with :ok <- user_can_list(conn, caller, camera),
         {:ok, timelapse} <- timelapse_exist(conn, timelapse_exid)
    do
      render(conn, "show.json", %{timelapse: timelapse})
    end
  end

  def create(conn, params) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(params["id"])

    with :ok <- user_can_list(conn, caller, camera)
    do
      timelapse_params =
        %{}
        |> add_parameter("field", :camera_id, camera.id)
        |> add_parameter("field", :user_id, caller.id)
        |> construct_timelapse_parameters(params, Camera.get_timezone(camera))

      case Timelapse.create_timelapse(timelapse_params) do
        {:ok, timelapse} ->
          start_timelapse_worker(Application.get_env(:evercam_media, :start_timelapse_workers), timelapse)
          render(conn |> put_status(:created), "show.json", %{timelapse: timelapse})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  def update(conn, %{"id" => camera_exid, "timelapse_id" => timelapse_exid} = params) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(camera_exid)

    with :ok <- user_can_list(conn, caller, camera),
         {:ok, timelapse} <- timelapse_exist(conn, timelapse_exid)
    do
      timelapse_params = construct_timelapse_parameters(%{}, params, Camera.get_timezone(camera))
      case Timelapse.update_timelapse(timelapse, timelapse_params) do
        {:ok, timelapse} ->
          update_timelapse_worker(Application.get_env(:evercam_media, :start_timelapse_workers), timelapse)
          render(conn, "show.json", %{timelapse: timelapse})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  def delete(conn, %{"id" => camera_exid, "timelapse_id" => timelapse_exid}) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(camera_exid)

    with :ok <- user_can_list(conn, caller, camera),
         {:ok, timelapse} <- timelapse_exist(conn, timelapse_exid)
    do
      stop_timelapse_worker(Application.get_env(:evercam_media, :start_timelapse_workers), timelapse)
      Timelapse.delete_by_id(timelapse.id)
      json(conn, %{})
    end
  end

  defp construct_timelapse_parameters(timelapse, params, timezone) do
    timelapse
    |> add_parameter("field", :title, params["title"])
    |> add_parameter("field", :frequency, params["frequency"])
    |> add_parameter("field", :status, params["status"])
    |> add_parameter("field", :date_always, params["date_always"])
    |> add_parameter("field", :time_always, params["time_always"])

    |> add_parameter("field", :snapshot_count, params["snapshot_count"])
    |> add_parameter("field", :resolution, params["resolution"])
    |> add_parameter("field", :watermark_logo, params["watermark_logo"])
    |> add_parameter("field", :watermark_position, params["watermark_position"])
    |> add_parameter("field", :recreate_hls, params["recreate_hls"])
    |> add_parameter("field", :start_recreate_hls, params["start_recreate_hls"])
    |> add_parameter("extra", :extra, params["extra"])

    |> add_datetime_parameter(:from_datetime, params["from_datetime"], timezone)
    |> add_datetime_parameter(:to_datetime, params["to_datetime"], timezone)
  end

  defp add_parameter(params, _field, _key, nil), do: params
  defp add_parameter(params, "field", key, value) do
    Map.put(params, key, value)
  end
  defp add_parameter(params, "extra", key, value) do
    Map.put(params, key, get_json(value))
  end

  defp add_datetime_parameter(params, _key, value, _timezone) when value in [nil, ""], do: params
  defp add_datetime_parameter(params, key, value, timezone) do
    datetime =
      value
      |> String.to_integer
      |> Calendar.DateTime.Parse.unix!
      |> Calendar.DateTime.to_erl
      |> Calendar.DateTime.from_erl!(timezone)
      |> Calendar.DateTime.shift_zone!("Etc/UTC")

    Map.put(params, key, datetime)
  end

  defp user_can_list(conn, user, camera) do
    case Permission.Camera.can_list?(user, camera) do
      true -> :ok
      _ -> render_error(conn, 403, "Forbidden.")
    end
  end

  defp timelapse_exist(conn, timelapse_exid) do
    case Timelapse.by_exid(timelapse_exid) do
      nil -> render_error(conn, 404, "Timelapse not found.")
      %Timelapse{} = timelapse -> {:ok, timelapse}
    end
  end

  defp get_json(schedule) do
    case Poison.decode(schedule) do
      {:ok, json} -> json
    end
  end

  defp start_timelapse_worker(true, timelapse) do
    spawn fn ->
      TimelapserSupervisor.start_timelapse_worker(timelapse)
    end
  end
  defp start_timelapse_worker(_mode, _timelapse), do: :noop

  defp update_timelapse_worker(true, timelapse) do
    spawn fn ->
      timelapse.exid
      |> String.to_atom
      |> Process.whereis
      |> TimelapserSupervisor.update_timelapse_worker(timelapse)
    end
  end
  defp update_timelapse_worker(_mode, _timelapse), do: :noop

  defp stop_timelapse_worker(true, timelapse) do
    spawn fn ->
      TimelapserSupervisor.stop_timelapse_worker(timelapse)
    end
  end
  defp stop_timelapse_worker(_mode, _timelapse), do: :noop
end
