defmodule EvercamMedia.SnapshotExtractor.ExtractorSupervisor do

  use Supervisor
  require Logger
  alias EvercamMedia.SnapshotExtractor.Extractor
  alias EvercamMedia.SnapshotExtractor.CloudExtractor
  alias EvercamMedia.SnapshotExtractor.TimelapseCreator
  import Commons

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Task.start_link(&initiate_workers/0)
    extractor_children = [worker(Extractor, [], restart: :permanent)]
    supervise(extractor_children, strategy: :simple_one_for_one, max_restarts: 1_000_000)
    cloud_extractor_childern = [worker(CloudExtractor, [], restart: :permanent)]
    supervise(cloud_extractor_childern, strategy: :simple_one_for_one, max_restarts: 1_000_000)
    timelapse_children = [worker(TimelaspeCreator, [], restart: :permanent)]
    supervise(timelapse_children, strategy: :simple_one_for_one, max_restarts: 1_000_000)
  end

  def initiate_workers do
    Logger.info "Initiate workers for extractor."
    #..Starting Local extractions.
    SnapshotExtractor.by_status(11)
    |> Enum.each(fn(extractor) ->
      spawn(fn ->
        extractor
        |> start_extraction(:local)
      end)
    end)

    #..Starting Cloud extractions.
    SnapshotExtractor.by_status(1)
    |> Enum.each(fn(extractor) ->
      spawn(fn ->
        extractor
        |> start_extraction(:cloud)
      end)
    end)

    #..Starting Timelapse extractions.
    SnapshotExtractor.by_status(21)
    |> Enum.each(fn(extractor) ->
      spawn(fn ->
        extractor
        |> start_extraction(:timelapse)
      end)
    end)
  end

  def start_extraction(nil, :local), do: :noop
  def start_extraction(nil, :cloud), do: :noop
  def start_extraction(nil, :timelapse), do: :noop
  def start_extraction(extractor, :local) do
    Logger.debug "Ressuming extraction for #{extractor.camera.exid}"
    Process.whereis(:"snapshot_extractor_#{extractor.id}")
    |> get_process_pid(EvercamMedia.SnapshotExtractor.Extractor, extractor.id)
    |> GenStage.cast({:snapshot_extractor, get_config(extractor, :local)})
  end
  def start_extraction(extractor, :cloud) do
    Logger.debug "Ressuming extraction for #{extractor.camera.exid}"
    Process.whereis(:"snapshot_extractor_#{extractor.id}")
    |> get_process_pid(EvercamMedia.SnapshotExtractor.CloudExtractor, extractor.id)
    |> GenStage.cast({:snapshot_extractor, get_config(extractor, :cloud)})
  end
  def start_extraction(extractor, :timelapse) do
    Logger.debug "Ressuming extraction for #{extractor.camera.exid}"
    Process.whereis(:"snapshot_extractor_#{extractor.id}")
    |> get_process_pid(EvercamMedia.SnapshotExtractor.TimelapseCreator, extractor.id)
    |> GenStage.cast({:snapshot_extractor, get_config(extractor, :timelapse)})
  end

  defp get_process_pid(nil, module, id) do
    case GenStage.start_link(module, {}, name: :"snapshot_extractor_#{id}") do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end
  defp get_process_pid(pid, _module, _id), do: pid

  def get_config(extractor, :cloud) do
  %{
    id: extractor.id,
    from_date: get_starting_date(extractor),
    to_date: extractor.to_date,
    interval: extractor.interval,
    schedule: extractor.schedule,
    camera_exid: extractor.camera.exid,
    timezone: extractor.camera.timezone,
    camera_name: extractor.camera.name,
    requestor: extractor.requestor,
    create_mp4: extractor.create_mp4,
    jpegs_to_dropbox: extractor.jpegs_to_dropbox,
    expected_count: get_count("#{@root_dir}/#{extractor.camera.exid}/extract/#{extractor.id}/") - 2
  }
  end
  def get_config(extractor, :local) do
    camera = Camera.by_exid_with_associations(extractor.camera.exid)
    host = Camera.host(camera, "external")
    port = Camera.port(camera, "external", "rtsp")
    cam_username = Camera.username(camera)
    cam_password = Camera.password(camera)
    url = camera.vendor_model.h264_url
    channel = url |> String.split("/channels/") |> List.last |> String.split("/") |> List.first
    %{
      exid: camera.exid,
      id: extractor.id,
      timezone: Camera.get_timezone(camera),
      host: host,
      port: port,
      username: cam_username,
      password: cam_password,
      channel: channel,
      start_date: get_starting_date(extractor),
      end_date: extractor.to_date,
      interval: extractor.interval,
      schedule: extractor.schedule,
      requester: extractor.requestor,
      create_mp4: serve_nil_value(extractor.create_mp4),
      jpegs_to_dropbox: serve_nil_value(extractor.jpegs_to_dropbox),
      inject_to_cr: serve_nil_value(extractor.inject_to_cr)
    }
  end
  def get_config(extractor, :timelapse) do
  %{
    id: extractor.id,
    from_date: get_starting_date(extractor),
    to_date: extractor.to_date,
    interval: extractor.interval,
    schedule: extractor.schedule,
    camera_exid: extractor.camera.exid,
    timezone: extractor.camera.timezone,
    camera_name: extractor.camera.name,
    requestor: extractor.requestor,
    create_mp4: extractor.create_mp4,
    jpegs_to_dropbox: extractor.jpegs_to_dropbox,
    expected_count: get_count("#{@root_dir}/#{extractor.camera.exid}/extract/#{extractor.id}/") - 2
  }
  end

  defp serve_nil_value(nil), do: false
  defp serve_nil_value(val), do: val

  defp get_starting_date(extractor) do
    {:ok, extraction_date} =
      File.read!("#{@root_dir}/#{extractor.camera.exid}/extract/#{extractor.id}/CURRENT")
      |> Calendar.DateTime.Parse.rfc3339_utc
    extraction_date
  end
end
