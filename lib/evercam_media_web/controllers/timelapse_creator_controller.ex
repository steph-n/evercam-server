defmodule EvercamMediaWeb.TimelapseCreatorController do
  use EvercamMediaWeb, :controller
  alias EvercamMediaWeb.SnapshotExtractorView
  alias EvercamMedia.Util
  import EvercamMedia.S3, only: [do_load_timelapse: 1]

  def timelapses_by_user(conn, _params) do
    caller = conn.assigns[:current_user]

    with :ok <- authorized(conn, caller)
    do
      timelapses = Timelapse.by_user_id(caller.id)
      render(conn, "index.json", %{timelapses: timelapses})
    end
  end

  def timelapses_by_camera(conn, %{"id" => exid}) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(exid)

    with :ok <- user_can_list(conn, caller, camera) do
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

  def play(conn, %{"id" => camera_exid, "archive_id" => timelapse_exid}) do
    caller = conn.assigns[:current_user]
    camera = Camera.get_full(camera_exid)

    with :ok <- user_can_list(conn, caller, camera),
         {:ok, timelapse} <- timelapse_exist(conn, timelapse_exid)
    do
      {content_type, content} =
        case do_load_timelapse("#{camera.exid}/#{timelapse.exid}/#{timelapse.exid}.#{timelapse.extra["format"]}") do
          {:ok, response} ->
            {get_content_type(timelapse.extra["format"]), response}
          {:error, _, _} ->
            evercam_logo_loader = Path.join(Application.app_dir(:evercam_media), "priv/static/images/evercam-logo-loader.gif")
            {"image/gif", File.read!(evercam_logo_loader)}
        end
      conn
      |> put_resp_header("content-type", content_type)
      |> text(content)
    end
  end

  defp get_content_type("gif"), do: "image/gif"
  defp get_content_type("mp4"), do: "video/mp4"

  def create(conn, video_params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.by_exid_with_associations(video_params["camera"])
    exid = Util.generate_unique_exid(video_params["title"])
    if upload = video_params["watermark_logo"] do
      File.cp!(upload.path, "media/#{upload.filename}")
    end
    logo =
      case upload do
        nil -> "false"
        _ -> upload.filename
      end
    snapshot_count = String.to_integer(video_params["duration"]) * 24
    params = %{
      from_datetime: video_params["from_datetime"] |> NaiveDateTime.from_iso8601! |> Calendar.DateTime.from_naive("Etc/UTC") |> elem(1),
      to_datetime: video_params["to_datetime"] |> NaiveDateTime.from_iso8601! |> Calendar.DateTime.from_naive("Etc/UTC") |> elem(1),
      exid: exid,
      watermark_logo: logo,
      camera_id: camera.id,
      user_id: current_user.id,
      snapshot_count: snapshot_count,
      date_always: true,
      time_always: true,
      title: video_params["title"],
      status: 6,
      description: video_params["description"],
      camera: video_params["camera"],
      frequency: video_params["duration"],
      extra: %{format: video_params["format"], rm_date: video_params["rm_date"]},
      resolution: video_params["resolution"],
      watermark_position: video_params["watermark_position"]
    }

    with :ok <- ensure_camera_exists(camera, exid, conn),
         {:ok, _} <- Timelapse.create_timelapse(params)
    do
      SnapshotExtractor.changeset(%SnapshotExtractor{}, %{
        camera_id: camera.id,
        from_date: video_params["from_datetime"] |> NaiveDateTime.from_iso8601! |> Calendar.DateTime.from_naive("Etc/UTC") |> elem(1),
        to_date: video_params["to_datetime"] |> NaiveDateTime.from_iso8601! |> Calendar.DateTime.from_naive("Etc/UTC") |> elem(1),
        interval: video_params["duration"],
        schedule: Jason.decode!(video_params["schedule"]),
        requestor: current_user.email,
        jpegs_to_dropbox: false,
        create_mp4: false,
        inject_to_cr: false,
        status: 21
      })
      |> Evercam.Repo.insert
      |> case do
        {:ok, extraction} ->
          full_snapshot_extractor = Repo.preload(extraction, :camera, force: true)
          config = %{
            id: full_snapshot_extractor.id,
            from_datetime: full_snapshot_extractor.from_date,
            to_datetime: full_snapshot_extractor.to_date,
            duration: full_snapshot_extractor.interval,
            schedule: full_snapshot_extractor.schedule,
            camera_exid: full_snapshot_extractor.camera.exid,
            timezone: full_snapshot_extractor.camera.timezone,
            camera_name: full_snapshot_extractor.camera.name,
            requestor: full_snapshot_extractor.requestor,
            create_mp4: full_snapshot_extractor.create_mp4,
            jpegs_to_dropbox: full_snapshot_extractor.jpegs_to_dropbox,
            expected_count: 0,
            watermark: video_params["watermark"],
            watermark_logo: logo,
            title: video_params["title"],
            rm_date: video_params["rm_date"],
            format: video_params["format"],
            headers: video_params["headers"],
            exid: exid,
          }
          extraction_pid = spawn(fn ->
            start_snapshot_extractor(config)
          end)
          :ets.insert(:extractions, {exid <> "-timelapse-#{full_snapshot_extractor.id}", extraction_pid})
          conn
          |> put_status(:created)
          |> put_view(SnapshotExtractorView)
          |> render("show.json", %{snapshot_extractor: full_snapshot_extractor})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  defp start_snapshot_extractor(config) do
    name = :"snapshot_extractor_#{config.id}"
    case Process.whereis(name) do
      nil ->
        {:ok, pid} = GenStage.start_link(EvercamMedia.SnapshotExtractor.TimelapseCreator, {}, name: name)
        pid
      pid -> pid
    end
    |> GenStage.cast({:snapshot_extractor, config})
  end

  defp user_can_list(conn, user, camera) do
    if !Permission.Camera.can_list?(user, camera) do
      render_error(conn, 403, "Forbidden.")
    else
      :ok
    end
  end

  defp timelapse_exist(conn, timelapse_exid) do
    case Timelapse.by_exid(timelapse_exid) do
      nil -> render_error(conn, 404, "Timelapse not found.")
      %Timelapse{} = timelapse -> {:ok, timelapse}
    end
  end

  defp ensure_camera_exists(nil, exid, conn) do
    render_error(conn, 404, "Camera '#{exid}' not found!")
  end
  defp ensure_camera_exists(_camera, _id, _conn), do: :ok
end
