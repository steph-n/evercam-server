defmodule EvercamMedia.SnapshotExtractor.TimelapseCreator do
  use Export.Python
  require Logger
  import EvercamMedia.Snapshot.Storage
  import Commons

  @format ~r[/(?<camera_exid>.*)/snapshots/recordings/(?<year>\d{4})/(?<month>\d{1,2})/(?<day>\d{1,2})/(?<hour>\d{1,2})/(?<minute>\d{2})_(?<seconds>\d{2})_(?<milliseconds>\d{3})\.jpg]

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  def init(args) do
    {:producer, args}
  end

  def handle_cast({:snapshot_extractor, config}, state) do
    _start_extractor(config)
    {:noreply, [], state}
  end

  def _start_extractor(extractor) do
    exid = extractor.exid
    requestor = extractor.requestor
    time_start = Calendar.DateTime.now_utc
    schedule = extractor.schedule
    duration = extractor.duration
    watermark = extractor.watermark
    watermark_logo = extractor.watermark_logo
    camera_exid = extractor.camera_exid
    title = extractor.title
    construction = construction(requestor)
    timezone = timezone(extractor.timezone)
    headers = extractor.headers
    format = extractor.format
    rm_date = extractor.rm_date
    video = Timelapse.by_exid(exid)

    start_date = erl_datetime(extractor.from_datetime, timezone)
    end_date = erl_datetime(extractor.to_datetime, timezone)

    total_days = find_difference(end_date, start_date) / 86400 |> round |> round_2

    File.mkdir_p(images_directory = "#{@root_dir}/#{camera_exid}/#{exid}")

    {:ok, c_agent} = Agent.start_link(fn -> 0 end)
    {:ok, i_agent} = Agent.start_link fn -> [] end

    1..total_days |> Enum.reduce(start_date, fn _i, acc ->
      day_of_week = acc |> Calendar.Date.day_of_week_name
      rec_head = get_head_tail(schedule[day_of_week])
      rec_head |> Enum.each(fn(x) ->
        iterate(x, start_date, end_date, acc, timezone) |> c_download(camera_exid, 3600, c_agent, i_agent)
      end)
      acc |> Calendar.DateTime.to_erl |> Calendar.DateTime.from_erl(timezone, {123456, 6}) |> ambiguous_handle |> Calendar.DateTime.add!(86400)
    end)

    c_count = Agent.get(c_agent, fn state -> state end) - available_count(images_directory)
    interval = get_interval(duration, c_count) |> intervaling

    e_start_date = start_date |> Calendar.Strftime.strftime!("%A, %b %d %Y, %H:%M")
    e_to_date = end_date |> Calendar.Strftime.strftime!("%A, %b %d %Y, %H:%M")
    e_interval = interval |> humanize_interval

    case c_count > 0 do
      true ->
        case Timelapse.update_timelapse(video, %{status: 9}) do
          {:ok, _extractor} ->
            send_mail_start(true, e_start_date, e_to_date, schedule, e_interval, camera_exid, requestor, duration)
            Agent.get(i_agent, fn list -> list end)
            |> Enum.filter(fn(item) -> item end)
            |> Enum.sort
            |> Enum.with_index(1)
            |> Enum.map(fn {url, acc} ->
              starting = get_timestamp(url)
              starting = Calendar.DateTime.Parse.unix!(starting)
              with true <- DateTime.compare(starting, start_date) == :lt or DateTime.compare(starting, end_date) == :gt
              do
                nil
              else
                _ -> {url, acc}
              end
            end)
            |> Enum.reject(&is_nil/1)
            |> Enum.map_every(interval, fn { url , _ } ->
              unix_date = url |> get_timestamp()
              File.write("#{@root_dir}/#{camera_exid}/#{exid}/CURRENT", "#{unix_date}")
              do_loop_duration(url, camera_exid, exid, construction)
            end)

            # create_mp4_file
            with {:ok, _extractor} <- Timelapse.update_timelapse(video, %{status: 8})
            do
              remove_date(images_directory, exid, rm_date)
              add_watermark(images_directory, exid, watermark)
              add_watermark_logo(images_directory, exid, watermark_logo)
              convert_to_gif(images_directory, exid, format)
              h_headers = get_headers(images_directory, exid, duration, headers)
              case Timelapse.update_timelapse(video, %{status: 10}) do
                {:ok, _extractor} ->
                  upload_timelapse(images_directory, exid, format, camera_exid, h_headers)
                _ -> Logger.info "Status update failed!"
              end

              time_end = Calendar.DateTime.now_utc
              count = get_count(images_directory) - 1

              {:ok, secs, _msecs, :after} = Calendar.DateTime.diff(time_end, time_start)
              execution_time = humanize_time(secs)
              clean_images(images_directory)
              case Timelapse.update_timelapse(video, %{status: 5}) do
                {:ok, _} ->
                  with {:ok, _full_extractor} <- SnapshotExtractor.by_id(extractor.id) |> SnapshotExtractor.update_snapshot_extactor(%{status: 22, notes: "Extracted Images = #{count} -- Expected Count = #{c_count}"})
                  do
                    send_mail_end(true, count, camera_exid, c_count, title, exid, requestor, execution_time, duration)
                  end
                _ -> Logger.info "Status update failed!"
              end
            end
          _ -> Logger.info "Status update failed!"
        end
      false ->
        case Timelapse.update_timelapse(video, %{status: 7}) do
          {:ok, _extractor} -> Logger.info "No Snapshots!"
          _ -> Logger.info "Status update failed!"
        end
    end
  end

  defp remove_date(images_directory, _exid, "false") do
    # ffmpeg -f image2pipe -framerate 24 -i - -c:v h264_nvenc -r 24 -preset fast -rc 1 -cbr true -pix_fmt yuv420p  -b:v 20000k -minrate 20000k -maxrate 20000k -bufsize 1835k -y output.mp4
    # Porcelain.shell("cat #{images_directory}/*.jpg | ffmpeg -f image2pipe -framerate 24 -i - -c:v h264_nvenc -r 24 -bufsize 1000k -pix_fmt yuv420p -y #{images_directory}/output.mp4", [err: :out]).out
    Porcelain.shell("cat #{images_directory}/*.jpg | ffmpeg -f image2pipe -framerate 24 -i - -c:v h264_nvenc -r 24 -preset fast -rc 1 -cbr true -pix_fmt yuv420p  -b:v 20000k -minrate 20000k -maxrate 20000k -bufsize 1835k -y #{images_directory}/output.mp4", [err: :out]).out
  end
  defp remove_date(images_directory, exid, "true") do
    {:ok, py} = Python.start(python: "python3", python_path: Path.expand("lib/python"))
    py |> Python.call(remove_date_2(exid, images_directory), from_file: "date_removal")
  end

  defp add_watermark( _images_directory, _exid, "false"), do: :noop
  defp add_watermark(images_directory, exid, "true") do
    Porcelain.shell("ffmpeg -i #{images_directory}/output.mp4 -i priv/static/images/evercam-logo-white.png -filter_complex '[0:v][1:v] overlay=W-w-15:H-h-15' -pix_fmt yuv420p -c:a copy #{images_directory}/#{exid}.mp4", [err: :out]).out
    File.rm_rf!("#{images_directory}/output.mp4")
    File.rename("#{images_directory}/#{exid}.mp4", "#{images_directory}/output.mp4")
  end

  defp add_watermark_logo(images_directory, exid, "false") do
    File.rename("#{images_directory}/output.mp4", "#{images_directory}/#{exid}.mp4")
  end
  defp add_watermark_logo(images_directory, exid, watermark_logo) do
    # File.cp!("media/#{watermark_logo}", "#{images_directory}/#{watermark_logo}")
    Porcelain.shell("ffmpeg -i media/#{watermark_logo} -vf scale=-1:180 #{images_directory}/#{watermark_logo}", [err: :out]).out
    Porcelain.shell("ffmpeg -i #{images_directory}/output.mp4 -i #{images_directory}/#{watermark_logo} -filter_complex '[0:v][1:v] overlay=15:H-h-15' -pix_fmt yuv420p -c:a copy #{images_directory}/#{exid}.mp4", [err: :out]).out
  end

  defp convert_to_gif(_images_directory, _exid, "mp4"), do: :noop
  defp convert_to_gif(images_directory, exid, "gif") do
    Porcelain.shell("ffmpeg -i #{images_directory}/#{exid}.mp4 -pix_fmt rgb24 -vf scale=426x240 #{images_directory}/#{exid}.gif", [err: :out]).out
  end
  defp get_headers(images_directory, exid, _duration, "false") do
    File.rename("#{images_directory}/output.mp4", "#{images_directory}/#{exid}.mp4")
    false
  end
  defp get_headers(images_directory, exid, duration, "true") do
    Porcelain.shell("ffmpeg -i #{images_directory}/#{exid}.mp4 -acodec libvo_aacenc -vcodec h264_nvenc -s 1920x1080 -r 60 -strict experimental #{images_directory}/h-#{exid}.mp4", [err: :out]).out
    File.rm!("#{images_directory}/#{exid}.mp4")
    Porcelain.shell("ffmpeg -i priv/static/video/intro.mp4 -i #{images_directory}/h-#{exid}.mp4 -f lavfi -i color=c=black:s=1920x1080 -filter_complex '[0:v]format=pix_fmts=yuva420p,fade=t=out:st=3:d=1:alpha=1,setpts=PTS-STARTPTS[va0];\
    [1:v]format=pix_fmts=yuv420p,fade=t=in:st=0:d=1:alpha=1,setpts=PTS-STARTPTS+3/TB[va1];\
    [2:v]scale=1920x1080,trim=duration=#{duration+2}[over];\
    [over][va0]overlay[over1];\
    [over1][va1]overlay=format=yuv420[outv]' -vcodec h264_nvenc -map [outv] #{images_directory}/out.mp4", [err: :out]).out
    Porcelain.shell("ffmpeg -i #{images_directory}/out.mp4 -i priv/static/video/contact.mp4 -f lavfi -i color=c=black:s=1920x1080 -filter_complex '[0:v]format=pix_fmts=yuva420p,fade=t=out:st=#{duration+2}:d=1:alpha=1,setpts=PTS-STARTPTS[va0];\
    [1:v]format=pix_fmts=yuv420p,fade=t=in:st=0:d=1:alpha=1,setpts=PTS-STARTPTS+#{duration}/TB[va1];\
    [2:v]scale=1920x1080,trim=duration=#{duration}[over];\
    [over][va0]overlay[over1];\
    [over1][va1]overlay=format=yuv420[outv]' -vcodec h264_nvenc -map [outv] #{images_directory}/#{exid}.mp4", [err: :out]).out
    "h-" <> exid <> ".mp4"
  end

  defp upload_timelapse(images_directory, exid, format, camera_exid, h_headers) do
    t_unique_filename = Path.wildcard("#{images_directory}/*.jpg") |> List.first()
    unique_filename = "#{images_directory}/#{exid}.#{format}"
    files = %{
      "#{unique_filename}" => "#{camera_exid}/#{exid}/#{exid}.#{format}",
      "#{t_unique_filename}" => "#{camera_exid}/#{exid}/thumb-video.jpg"
    }
    case h_headers do
      false -> Logger.info "No headers"
      _ ->
        h_unique_filename = "#{images_directory}/#{h_headers}"
        Map.put(files, "#{h_unique_filename}", "#{camera_exid}/#{exid}/h-#{exid}.mp4")
    end
    do_save_multiple(files)
  end

  defp do_save_multiple(paths) do
    upload_file = fn {src_path, dest_path} ->
      ExAws.S3.put_object("evercam-timelapse", dest_path, File.read!(src_path))
      |> ExAws.request!
    end
    paths
    |> Task.async_stream(upload_file, max_concurrency: 10, timeout: :infinity)
    |> Stream.run
  end

  defp c_download([], _camera_exid, _interval, _c_agent, _i_agent), do: :noop
  defp c_download([starting, ending], camera_exid, interval, c_agent, i_agent) do
    c_do_loop(starting, ending, camera_exid, interval, c_agent, i_agent)
  end

  defp c_do_loop(starting, ending, _camera_exid, _interval, _c_agent, _i_agent) when starting >= ending, do: Logger.info "We are finished!"
  defp c_do_loop(starting, ending, camera_exid, interval, c_agent, i_agent) do
    #Agent.update(c_agent, fn list -> ["true" | list] end)
    count_files(starting, ending, camera_exid, interval, c_agent, i_agent)
  end

  defp do_loop_duration(url, camera_exid, id, construction) do
    starting =
      url
      |> get_timestamp()
    filer =
      starting
      |> point_to_seaweed()
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 15000]
    with {:ok, response} <- HTTPoison.get("#{filer.url}#{url}", ["Accept": "application/json"], hackney: hackney),
         %HTTPoison.Response{status_code: 200, body: body} <- response do
      upload(200, body, starting, camera_exid, id, construction)
    else
      _ -> :noop
    end
  end

  defp url_to_erl(url) do
    %{
      "day" => day,
      "hour" => hour,
      "minute" => minutes,
      "month" => month,
      "seconds" => seconds,
      "year" => year
    } = Regex.named_captures(@format, url)
    {{String.to_integer(year), String.to_integer(month), String.to_integer(day)}, {String.to_integer(hour), String.to_integer(minutes), String.to_integer(seconds)}}
  end

  defp get_timestamp(url) do
    url_to_erl(url)
    |> Calendar.DateTime.from_erl("UTC")
    |> ambiguous_handle()
    |> Calendar.DateTime.Format.unix
  end

  defp count_files(starting, ending, _camera_exid, _interval, _c_agent, _i_agent) when starting >= ending, do: Logger.info "We are finished!"
  defp count_files(starting, ending, camera_exid, interval, c_agent, i_agent) do
    %{year: year, month: month, day: day, hour: hour, min: _, sec: _} = make_me_complete(starting)
    filer = point_to_seaweed(starting)
    url = "#{filer.url}/#{camera_exid}/snapshots/recordings/#{year}/#{month}/#{day}/#{hour}/?limit=3600"
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 15000]
    with {:ok, response} <- HTTPoison.get(url, ["Accept": "application/json"], hackney: hackney),
         %HTTPoison.Response{status_code: 200, body: body} <- response,
         {:ok, data} <- Jason.decode(body) do
      sum = data[filer.files] |> is_nil() |> count_filer(data, filer.files)
      Agent.get_and_update(c_agent, fn state -> {state, state + sum} end)
      Enum.map(data[filer.files], fn x ->
        Agent.update(i_agent, fn list -> [x[filer.name] | list] end)
      end)
      count_files(starting + interval, ending, camera_exid, interval, c_agent, i_agent)
    else
      _ -> :noop
    end
  end

  defp count_filer(true, _my_json, _attribute), do: 0
  defp count_filer(_, my_json, attribute), do: do_count(my_json, attribute)

  defp do_count(json, attribute), do: json[attribute] |> Enum.count

  defp upload(200, response, starting, camera_exid, id, _construction) do
    image_save_path = "#{@root_dir}/#{camera_exid}/#{id}/#{starting}.jpg"
    imagef = File.write(image_save_path, response, [:binary])
    File.close imagef
  end
  defp upload(_, response, _starting, _camera_exid, _id, _construction), do: Logger.info "Not an Image! #{response}"

  defp iterate([], _start_date, _end_date,  _check_time, _timezone), do: []
  defp iterate([head], start_date, end_date, check_time, timezone) do
    [from_hour, to_hour] = String.split head, "-"
    from_minute = "00"
    to_minute = "59"
    %{year: year, month: month, day: day, hour: hour} = start_date
    erl_date_time = {{year, month, day}, {hour, 0, 0}}
    my_start = Calendar.DateTime.from_erl(erl_date_time, timezone) |> ambiguous_handle() |> Calendar.DateTime.Format.unix
    %{year: year, month: month, day: day, hour: hour} = Timex.shift(end_date, hours: 1)
    erl_date_time = {{year, month, day}, {hour, 0, 0}}
    my_end = Calendar.DateTime.from_erl(erl_date_time, timezone) |> ambiguous_handle() |> Calendar.DateTime.Format.unix
    from_unix_timestamp = unix_timestamp(from_hour, from_minute, check_time, timezone)
    to_unix_timestamp = unix_timestamp(to_hour, to_minute, check_time, timezone)
    [max(from_unix_timestamp, my_start), min(to_unix_timestamp, my_end)]
  end

  defp send_mail_start(false, _e_start_date, _e_to_date, _e_schedule, _e_interval, _camera_name, _requestor, _duration), do: Logger.info "We are in Development Mode!"
  defp send_mail_start(true, e_start_date, e_to_date, e_schedule, e_interval, camera_name, requestor, duration), do: EvercamMedia.UserMailer.timelapse_creator_started(e_start_date, e_to_date, e_schedule, e_interval, camera_name, requestor, duration)

  defp send_mail_end(false, _count, _camera_name, _expected_count, _extractor_id, _camera_exid, _requestor, _execution_time, _duration), do: Logger.info "We are in Development Mode!"
  defp send_mail_end(true, count, camera_name, expected_count, extractor_id, camera_exid, requestor, execution_time, duration), do: EvercamMedia.UserMailer.timelapse_creator_completed(count, camera_name, expected_count, extractor_id, camera_exid, requestor, execution_time, duration)

  defp make_me_complete(date) do
    # %{year: year, month: month, day: day, hour: hour, min: min, sec: sec} = Calendar.DateTime.Parse.unix! date
    {{year, month, day}, {hour, min, sec}} = Calendar.DateTime.Parse.unix!(date) |> Calendar.DateTime.to_erl
    month = String.pad_leading("#{month}", 2, "0")
    day = String.pad_leading("#{day}", 2, "0")
    hour = String.pad_leading("#{hour}", 2, "0")
    min = String.pad_leading("#{min}", 2, "0")
    sec = String.pad_leading("#{sec}", 2, "0")
    %{year: year, month: month, day: day, hour: hour, min: min, sec: sec}
  end

  defp humanize_interval(n), do: "1 Frame in #{n}"

  defp get_interval(duration, c_count) do
    interval = c_count / (duration * 24)
    case interval do
      nil -> false
      _ -> Kernel.trunc(interval)
    end
  end

  defp available_count(dir) do
    File.ls(dir)
    |> ls_files()
  end

  defp ls_files({:error, :enoent}), do: 0
  defp ls_files({:ok, files}) do
    Enum.count(files, fn file -> Path.extname(file) == ".jpg" end)
    |> ls_count()
  end

  defp ls_count([]), do: 0
  defp ls_count(count), do: count

  defp construction("marklensmen@gmail.com"), do: "Construction"
  defp construction(_), do: "Construction2"

  defp timezone(nil), do: "Etc/UTC"
  defp timezone(timezone), do: timezone

  defp erl_datetime(datetime, timezone) do
    datetime
    |> Calendar.DateTime.to_erl
    |> Calendar.DateTime.from_erl!(timezone)
  end
end
