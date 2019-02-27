defmodule EvercamMedia.Timelapse.TimelapserSupervisor do
  @moduledoc """
  Provides function to manage timelapse workers
  """

  use Supervisor
  require Logger
  alias EvercamMedia.Timelapse.Timelapser

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    if Application.get_env(:evercam_media, :start_timelapse_workers) do
      Task.start_link(&initiate_workers/0)
    end
    children = [worker(Timelapser, [], restart: :permanent)]
    supervise(children, strategy: :simple_one_for_one, max_restarts: 1_000_000)
  end

  @doc """
  Start timelapse worker
  """
  def start_timelapse_worker(nil), do: :noop
  def start_timelapse_worker(timelapse) do
    case get_config(timelapse) do
      {:ok, settings} ->
        Logger.debug "[#{settings.name}] Starting timelapse worker"
        Supervisor.start_child(__MODULE__, [settings])
      {:error, _message, url} ->
        Logger.warn "[#{timelapse.exid}] Skipping timelapse worker as the host is invalid: #{url}"
    end
  end

  @doc """
  Reinitialize timelapse worker with new configuration
  """
  def update_timelapse_worker(nil, _timelapse), do: :noop
  def update_timelapse_worker(worker, timelapse) do
    case get_config(timelapse) do
      {:ok, settings} ->
        Logger.debug "Updating worker for #{settings.name}"
        Timelapser.update_config(worker, settings)
      {:error, _message} ->
        Logger.info "Skipping timelapse worker update as the arguments are invalid"
    end
  end

  @doc """
  Stop timelapse process
  """
  def stop_timelapse_worker(timelapse) do
    Supervisor.terminate_child(__MODULE__, timelapse.exid |> String.to_atom |> Process.whereis)
  end

  @doc """
  Start a worker for each timelapse in the database.

  This function is intended to be called after the EvercamMedia.Timelapse.TimelapserSupervisor
  is initiated.
  """
  def initiate_workers do
    Logger.info "Initiate workers for timelapse."
    Timelapse.all |> Enum.map(&(start_timelapse_worker &1))
  end

  @doc """
  Given a timelapse, it returns a map of values required for starting a timelapse worker.
  """
  def get_config(timelapse) do
    create_directory_structure(timelapse.camera.exid, timelapse.exid)
    {
      :ok,
      %{
        name: timelapse.exid |> String.to_atom,
        config: %{
          timelapse_id: timelapse.id,
          camera_exid: timelapse.camera.exid,
          camera_name: timelapse.camera.name,
          title: timelapse.title,
          url: Camera.snapshot_url(timelapse.camera),
          auth: Camera.get_auth_type(timelapse.camera),
          username: Camera.username(timelapse.camera),
          password: Camera.password(timelapse.camera),
          vendor_exid: Camera.get_vendor_attr(timelapse.camera, :exid),
          timezone: Camera.get_timezone(timelapse.camera),
          date_always: timelapse.date_always,
          time_always: timelapse.time_always,
          from_datetime: timelapse.from_datetime,
          to_datetime: timelapse.to_datetime,
          status: timelapse.status,
          sleep: timelapse.frequency * 60 * 1000
        }
      }
    }
  end

  defp create_directory_structure(camera_id, timelapse_id) do
    timelapse_path = "#{@root_dir}/#{camera_id}/timelapses/#{timelapse_id}/"
    File.mkdir_p(timelapse_path)
    File.mkdir_p("#{timelapse_path}ts")
    File.mkdir_p("#{timelapse_path}images")
    create_bash_file(timelapse_path)
    create_manifest_file(camera_id, timelapse_id)
  end

  defp create_bash_file(timelapse_path) do
    images_path = "#{timelapse_path}images/"
    ts_path = "#{timelapse_path}ts/"

    bash_content = "#!/bin/bash"
    bash_content = bash_content <> "\nffmpeg -threads 1 -y -framerate 24 -i #{images_path}/%d.jpg -c:v libx264 -pix_fmt yuv420p -preset slow -tune stillimage -b:v 64K -maxrate 10000k -bufsize 64k -crf 28 -r 24 -f hls -hls_time 2 -hls_list_size 0 #{ts_path}/low.m3u8"
    bash_content = bash_content <> "\nffmpeg -threads 1 -y -framerate 24 -i #{images_path}/%d.jpg -c:v libx264 -pix_fmt yuv420p -preset slow -tune stillimage -b:v 64K -maxrate 13000k -bufsize 64k -crf 28 -r 24 -f hls -hls_time 2 -hls_list_size 0 #{ts_path}/medium.m3u8"
    bash_content = bash_content <> "\nffmpeg -threads 1 -y -framerate 24 -i #{images_path}/%d.jpg -c:v libx264 -pix_fmt yuv420p -preset slow -tune stillimage -b:v 64K -maxrate 16000k -bufsize 64k -crf 28 -r 24 -f hls -hls_time 2 -hls_list_size 0 #{ts_path}/high.m3u8"
    File.write("#{timelapse_path}build.sh", bash_content)
  end

  defp create_manifest_file(camera_exid, timelapse_id) do
    m3u8_file = "#EXTM3U"
    m3u8_file = m3u8_file <> "\n#EXT-X-STREAM-INF:BANDWIDTH=500000"
    m3u8_file = m3u8_file <> "\nts/low.m3u8"
    m3u8_file = m3u8_file <> "\n#EXT-X-STREAM-INF:BANDWIDTH=1000000"
    m3u8_file = m3u8_file <> "\nts/medium.m3u8"
    m3u8_file = m3u8_file <> "\n#EXT-X-STREAM-INF:BANDWIDTH=4000000"
    m3u8_file = m3u8_file <> "\nts/high.m3u8"
    EvercamMedia.Snapshot.Storage.save_timelapse_manifest(camera_exid, timelapse_id, m3u8_file)
  end
end
