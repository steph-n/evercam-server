defmodule EvercamMedia.SnapshotExtractor.ExtractorSupervisor do

  use Supervisor
  require Logger
  alias EvercamMedia.SnapshotExtractor.Extractor

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    Task.start_link(&initiate_workers/0)
    children = [worker(Extractor, [], restart: :permanent)]
    supervise(children, strategy: :simple_one_for_one, max_restarts: 1_000_000)
  end

  def initiate_workers do
    Logger.info "Initiate workers for extractor."
    SnapshotExtractor.by_status(11)
    |> Enum.each(fn(extractor) ->
      extraction_pid = spawn(fn ->
        extractor
        |> start_extraction()
      end)
      :ets.insert(:extractions, {extractor.camera.exid, extraction_pid})
    end)
  end

  def start_extraction(nil), do: :noop
  def start_extraction(extractor) do
    Logger.debug "Ressuming extraction for #{extractor.camera.exid}"
    Process.whereis(:snapshot_extractor)
    |> get_process_pid
    |> GenStage.cast({:snapshot_extractor, get_config(extractor)})
  end

  defp get_process_pid(nil) do
    case GenStage.start_link(EvercamMedia.SnapshotExtractor.Extractor, {}, name: :snapshot_extractor) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end
  defp get_process_pid(pid), do: pid

  def get_config(extractor) do
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

  defp serve_nil_value(nil), do: false
  defp serve_nil_value(val), do: val

  defp get_starting_date(extractor) do
    {:ok, extraction_date} =
      File.read!("#{@root_dir}/#{extractor.camera.exid}/extract/#{extractor.id}/CURRENT")
      |> Calendar.DateTime.Parse.rfc3339_utc
    extraction_date
  end
end
