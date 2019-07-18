defmodule EvercamMedia.SnapshotExtractor.Extractor do
  @moduledoc """
  Provides functions to extract images from NVR recordings
  """

  use GenStage
  require Logger
  import EvercamMedia.SnapshotExtractor.ExtractorSchedule, only: [scheduled_now?: 3]
  import EvercamMedia.Snapshot.Storage, only: [seaweedfs_save_sync: 4]

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  ######################
  ## Server Callbacks ##
  ######################

  @doc """
  Initialize the snapmail server
  """
  def init(args) do
    {:producer, args}
  end

  @doc """
  """
  def handle_cast({:snapshot_extractor, config}, state) do
    _start_extractor(state, config)
    {:noreply, [], state}
  end

  #####################
  # Private functions #
  #####################

  defp _start_extractor(_state, config) do
    spawn fn ->
      start_date = config.start_date |> Calendar.DateTime.shift_zone(config.timezone) |> elem(1)
      end_date = config.end_date |> Calendar.DateTime.shift_zone(config.timezone) |> elem(1)
      url = nvr_url(config.host, config.port, config.username, config.password, config.channel)
      images_directory = "#{@root_dir}/#{config.exid}/extract/#{config.id}/"
      upload_path =
        case config.requester do
          "marklensmen@gmail.com" ->
            "/Construction/#{config.exid}/#{config.id}/"
          _ ->
            "/Construction2/#{config.exid}/#{config.id}/"
        end
      File.mkdir_p(images_directory)
      kill_ffmpeg_pids(config.host, config.port, config.username, config.password)
      {:ok, _, _, status} = Calendar.DateTime.diff(start_date, end_date)
      iterate(status, config, url, start_date, end_date, images_directory, upload_path)
    end
  end

  defp iterate(:before, config, url, start_date, end_date, path, upload_path) do
    case scheduled_now?(config.schedule, start_date, config.timezone) do
      {:ok, true} ->
        Logger.debug "Extracting snapshot from NVR."
        extract_image(config, url, start_date, path, upload_path, config.timezone)
      {:ok, false} ->
        Logger.debug "Not Scheduled. Skip extracting snapshot from NVR."
      {:error, _message} ->
        Logger.error "Error getting scheduler snapshot from NVR."
    end
    next_start_date = start_date |> Calendar.DateTime.advance!(config.interval)
    {:ok, _, _, status} = Calendar.DateTime.diff(next_start_date, end_date)
    iterate(status, config, url, next_start_date, end_date, path, upload_path)
  end
  defp iterate(_status, config, _url, start_date, end_date, path, upload_path) do
    :timer.sleep(:timer.seconds(5))
    snapshot_count = get_count(path)
    create_video_mp4(config.create_mp4, config, path, upload_path)
    update_snapshot_extractor(config, snapshot_count)
    Logger.debug "Start date (#{start_date}) greater than end date (#{end_date})."
  end

  def create_video_mp4(status, config, path, upload_path) when status in [true, "true"] do
    Porcelain.shell("cat #{path}*.jpg | ffmpeg -f image2pipe -framerate 6 -i - -c:v h264_nvenc -r 6 -preset slow -bufsize 1000k -pix_fmt yuv420p -y #{path}#{config.exid}.mp4", [err: :out]).out
    spawn(fn ->
      File.exists?("#{path}#{config.exid}.mp4")
      |> upload_image("#{path}#{config.exid}.mp4", "#{upload_path}#{config.exid}.mp4")
      clean_images(path)
      :ets.delete(:extractions, config.exid)
    end)
  end
  def create_video_mp4(_, config, path, _upload_path) do
    :ets.delete(:extractions, config.exid)
    clean_images(path)
  end

  defp update_snapshot_extractor(config, snapshot_count) do
    snapshot_extractor = SnapshotExtractor.by_id(config.id)
    EvercamMedia.UserMailer.snapshot_extraction_completed(snapshot_extractor, snapshot_count)
    params = %{status: 12, notes: "Extracted images = #{snapshot_count}"}
    SnapshotExtractor.update_snapshot_extactor(snapshot_extractor, params)
  end

  defp get_count(images_path) do
    case File.exists?(images_path) do
      true ->
        Enum.count(File.ls!(images_path))
      _ ->
        0
    end
  end

  defp extract_image(config, url, start_date, path, upload_path, timezone) do
    image_name = start_date |> Calendar.DateTime.Format.rfc3339
    saved_file_name = start_date |> DateTime.to_unix
    images_path = "#{path}#{saved_file_name}.jpg"
    upload_image_path = "#{upload_path}#{image_name}.jpg"
    save_current_jpeg_time(image_name, path)
    startdate_iso = convert_to_iso(start_date)
    enddate_iso = start_date |> Calendar.DateTime.advance!(10) |> convert_to_iso
    stream_url = "#{url}?starttime=#{startdate_iso}&endtime=#{enddate_iso}"
    Porcelain.shell("ffmpeg -rtsp_transport tcp -stimeout 10000000 -i '#{stream_url}' -vframes 1 -y #{images_path}").out
    spawn(fn ->
      File.exists?(images_path)
      |> upload_and_inject_image(config, images_path, upload_image_path, start_date, timezone)
    end)
  end

  defp upload_and_inject_image(true, config, image_path, upload_image_path, start_date, timezone) do
    upload_image(config.jpegs_to_dropbox, image_path, upload_image_path)
    inject_to_cr(config.inject_to_cr, config.exid, image_path, start_date, timezone)
  end
  defp upload_and_inject_image(_, _config, _image_path, _upload_image_path, _start_date, _timezone), do: :noop

  defp inject_to_cr(status, exid, image_path, start_date, timezone)  when status in [true, "true"] do
    {:ok, image} = File.read("#{image_path}")
    seaweedfs_save_sync(exid, shift_zone_to_utc(start_date, timezone) |> DateTime.to_unix, image, "Evercam Proxy")
  end
  defp inject_to_cr(_, _exid, _image_path, _start_date, _timezone), do: :noop

  defp upload_image(status, image_path, upload_image_path) when status in [true, "true"] do
    client = ElixirDropbox.Client.new(System.get_env["DROP_BOX_TOKEN"])
    {:ok, file_size} = get_file_size(image_path)
    %{"session_id" => session_id} = ElixirDropbox.Files.UploadSession.start(client, false, image_path)
    ElixirDropbox.Files.UploadSession.finish(client, session_id, upload_image_path, image_path, file_size) |> handle_upload_response
  end
  defp upload_image(_status, _image_path, _upload_image_path), do: :noop

  defp handle_upload_response({{:status_code, status_code}, {:ok, %{ "error" => %{ ".tag" => tag, "lookup_failed" => lookup_failed}, "error_summary" => error_summary }}}), do:
    Logger.info "status_code: #{status_code} error_tag: #{tag} lookup_failed: #{lookup_failed} error_summary: #{error_summary}"
  defp handle_upload_response(_), do: :noop

  defp save_current_jpeg_time(name, path) do
    File.write!("#{path}CURRENT", name)
  end

  defp nvr_url(ip, port, username, password, channel) do
    "rtsp://#{username}:#{password}@#{ip}:#{port}/Streaming/tracks/#{channel}"
  end

  defp convert_to_iso(datetime) do
    datetime
    |> Calendar.Strftime.strftime!("%Y%m%dT%H%M%SZ")
  end

  defp kill_ffmpeg_pids(ip, port, username, password) do
    rtsp_url = "rtsp://#{username}:#{password}@#{ip}:#{port}/Streaming/tracks/"
    Porcelain.shell("ps -ef | grep ffmpeg | grep '#{rtsp_url}' | grep -v grep | awk '{print $2}'").out
    |> String.split
    |> Enum.each(fn(pid) -> Porcelain.shell("kill -9 #{pid}") end)
  end

  defp clean_images(images_directory) do
    File.rm_rf!(images_directory)
  end

  defp shift_zone_to_utc(date, timezone) do
    %{year: year, month: month, day: day, hour: hour, minute: minute, second: second} = date
    Calendar.DateTime.from_erl!({{year, month, day}, {hour, minute, second}}, timezone)
    |> Calendar.DateTime.shift_zone!("UTC")
  end

  defp get_file_size(image_path) do
    case File.stat(image_path) do
      {:ok, %File.Stat{size: size}} -> {:ok, size}
      {:error, reason} -> {:error, reason}
    end
  end
end
