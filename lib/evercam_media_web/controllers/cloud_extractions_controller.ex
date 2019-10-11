defmodule EvercamMediaWeb.CloudExtractionsController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  alias EvercamMediaWeb.SnapshotExtractorView
  alias EvercamMedia.Util

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  swagger_path :create do
    post "/cameras/{id}/apps/cloud-extractions"
    summary "Create new cloud extraction of given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      from_date :path, :string, "ISO8601 (2019-02-18T09:00:00.000+00:00)", required: true
      to_date :path, :string, "ISO8601 (2019-02-18T09:00:00.000+00:00)", required: true
      requestor :path, :string, "Email of the person requesting extraction.", required: true
      interval :query, :string, "", required: true, enum: ["5", "10", "15", "20", "30", "60", "300", "600", "900", "1200", "1800", "3600", "7200", "21600", "43200", "86400"]
      schedule :query, :string, "For example in json format {\"Wednesday\":[\"8:0-18:0\"],\"Tuesday\":[\"8:0-18:0\"]}", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Recordings"
    response 200, "Success"
    response 401, "Invalid API keys"
    response 403, "Unauthorized"
  end

  def create(conn, %{"id" => exid} = params) do
    current_user = conn.assigns[:current_user]
    camera = Camera.by_exid_with_associations(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_edit(current_user, camera, conn)
    do
      SnapshotExtractor.changeset(%SnapshotExtractor{}, %{
        camera_id: camera.id,
        from_date: params["from_date"] |> NaiveDateTime.from_iso8601! |> Calendar.DateTime.from_naive("Etc/UTC") |> elem(1),
        to_date: params["to_date"] |> NaiveDateTime.from_iso8601! |> Calendar.DateTime.from_naive("Etc/UTC") |> elem(1),
        interval: params["interval"],
        schedule: Jason.decode!(params["schedule"]),
        requestor: params["requestor"],
        jpegs_to_dropbox: true,
        create_mp4: false,
        inject_to_cr: false,
        status: 1
      })
      |> Evercam.Repo.insert
      |> case do
        {:ok, extraction} ->
          full_snapshot_extractor = Repo.preload(extraction, :camera, force: true)
          config = %{
            id: full_snapshot_extractor.id,
            from_date: full_snapshot_extractor.from_date,
            to_date: full_snapshot_extractor.to_date,
            interval: full_snapshot_extractor.interval,
            schedule: full_snapshot_extractor.schedule,
            camera_exid: full_snapshot_extractor.camera.exid,
            timezone: full_snapshot_extractor.camera.timezone,
            camera_name: full_snapshot_extractor.camera.name,
            requestor: full_snapshot_extractor.requestor,
            create_mp4: full_snapshot_extractor.create_mp4,
            jpegs_to_dropbox: full_snapshot_extractor.jpegs_to_dropbox,
            expected_count: 0
          }
          spawn(fn ->
            EvercamMedia.UserMailer.snapshot_extraction_started(full_snapshot_extractor, "Cloud")
            start_snapshot_extractor(config)
          end)
          conn
          |> put_status(:created)
          |> put_view(SnapshotExtractorView)
          |> render("show.json", %{snapshot_extractor: full_snapshot_extractor})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  def show(conn, %{"id" => exid, "extraction_id" => extraction_id}) do
    with  pid          <- Process.whereis(:"snapshot_extractor_#{extraction_id}"),
          true         <- pid != nil,
          {:ok, files} <- File.ls("#{@root_dir}/#{exid}/extract/#{extraction_id}/") do
      json(conn, %{status: :up, jpegs: count_jpegs(files)})
    else
      {:ok, ["CURRENT"]} -> json(conn, %{status: :down, jpegs: 0})
      _ -> json(conn, %{status: :down, jpegs: 0})
    end
  end

  swagger_path :delete_extraction do
    delete "/cameras/{id}/apps/cloud-recording/extract"
    summary "Delete the cloud extraction"
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      extraction_id :query, :integer, "Extraction ID for the deletion of cloud extraction.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Recordings"
    response 200, "Success"
    response 401, "Invalid API keys or Unauthorized"
    response 404, "Snapshot extraction not found"
  end

  def delete_extraction(conn, %{"id" => exid, "extraction_id" => extraction_id}) do
    with {1, nil}       <- SnapshotExtractor.delete_by_id(extraction_id) do
      spawn(fn ->
        Process.whereis(:"snapshot_extractor_#{extraction_id}")
        |> case do
          nil -> :noop
          pid -> Process.exit(pid, :kill)
        end
        File.rm_rf("#{@root_dir}/#{exid}/extract/#{extraction_id}/")
      end)
      json(conn, %{message: "Cloud Extraction has been deleted for camera: #{exid}"})
   else
    _ ->
      json(conn, %{message: "Cloud Extraction is not running for this camera."})
   end
  end


  defp ensure_camera_exists(nil, exid, conn) do
    render_error(conn, 404, "Camera '#{exid}' not found!")
  end
  defp ensure_camera_exists(_camera, _id, _conn), do: :ok

  defp ensure_can_edit(current_user, camera, conn) do
    case Permission.Camera.can_edit?(current_user, camera) do
      true -> :ok
      _ -> render_error(conn, 403, %{message: "You don't have sufficient rights for this."})
    end
  end

  defp start_snapshot_extractor(config) do
    name = :"snapshot_extractor_#{config.id}"
    case Process.whereis(name) do
      nil ->
        {:ok, pid} = GenStage.start_link(EvercamMedia.SnapshotExtractor.CloudExtractor, {}, name: name)
        pid
      pid -> pid
    end
    |> GenStage.cast({:snapshot_extractor, config})
  end

  defp count_jpegs(files), do: files |> Enum.filter(&String.ends_with?(&1, ".jpg")) |> Enum.count()
end
