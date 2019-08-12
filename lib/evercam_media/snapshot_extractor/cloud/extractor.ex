defmodule EvercamMedia.SnapshotExtractor.CloudExtractor do
  use GenStage
  require Logger
  import Commons
  import EvercamMedia.Snapshot.Storage

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  ######################
  ## Server Callbacks ##
  ######################

  def init(args) do
    {:producer, args}
  end

  def handle_cast({:snapshot_extractor, config}, state) do
    _start_extractor(config)
    {:noreply, [], state}
  end

  #####################
  # Private functions #
  #####################

  def _start_extractor(extractor) do
    time_start = Calendar.DateTime.now_utc
    schedule = extractor.schedule
    interval = extractor.interval |> intervaling
    requestor = extractor.requestor
    camera_exid = extractor.camera_exid

    timezone =
      case extractor.timezone do
        nil -> "Etc/UTC"
        _ -> extractor.timezone
      end

    start_date =
      extractor.from_date
      |> Calendar.DateTime.to_erl
      |> Calendar.DateTime.from_erl!(timezone)

    end_date =
      extractor.to_date
      |> Calendar.DateTime.to_erl
      |> Calendar.DateTime.from_erl!(timezone)

    total_days = find_difference(end_date, start_date) / 86400 |> round |> round_2

    File.mkdir_p(images_directory = "#{@root_dir}/#{camera_exid}/extract/#{extractor.id}/")

    {_last_date, expected_count} =
      Enum.reduce(1..total_days, {start_date, 0}, fn _i, {dates, counts} ->
        day_of_week = Calendar.Date.day_of_week_name(dates)
        more_counts =
          schedule[day_of_week]
          |> get_head_tail()
          |> Enum.map(fn(x) ->
            x
            |> iterate(dates, timezone)
            |> count_download(interval)
          end)
          |> Enum.sum()
        dates =
          dates
          |> Calendar.DateTime.to_erl()
          |> Calendar.DateTime.from_erl(timezone, {123456, 6})
          |> ambiguous_handle()
          |> Calendar.DateTime.add!(86400)

        {dates, more_counts + counts}
      end)

    1..total_days |> Enum.reduce(start_date, fn _i, acc ->
      filer = point_to_seaweed(acc)
      url_day = "#{filer.url}/#{camera_exid}/snapshots/recordings/"
      with :ok <- ensure_a_day(acc, url_day)
      do
        day_of_week = acc |> Calendar.Date.day_of_week_name
        rec_head = get_head_tail(schedule[day_of_week])
        rec_head |> Enum.each(fn(x) ->
          iterate(x, acc, timezone) |> download(camera_exid, interval, extractor.id, requestor)
        end)
        acc |> Calendar.DateTime.to_erl |> Calendar.DateTime.from_erl(timezone, {123456, 6}) |> ambiguous_handle |> Calendar.DateTime.add!(86400)
      else
        :not_ok ->
          acc |> Calendar.DateTime.to_erl |> Calendar.DateTime.from_erl(timezone, {123456, 6}) |> ambiguous_handle |> Calendar.DateTime.add!(86400)
      end
    end)

    commit_if_1000(1000, ElixirDropbox.Client.new(System.get_env["DROP_BOX_TOKEN"]), images_directory)

    time_end = Calendar.DateTime.now_utc
    count = get_count(images_directory) - 1

    {:ok, secs, _msecs, :after} = Calendar.DateTime.diff(time_end, time_start)
    execution_time = humanize_time(secs)
    clean_images(images_directory)
    :ets.delete(:extractions, camera_exid <> "-cloud-#{extractor.id}")
    case SnapshotExtractor.by_id(extractor.id) |> SnapshotExtractor.update_snapshot_extactor(%{status: 2, notes: "Extracted Images = #{count} -- Expected Count = #{expected_count}"}) do
      {:ok, full_extractor} ->
        send_mail_end(Application.get_env(:evercam_media, :run_spawn), full_extractor, count, expected_count + extractor.expected_count, execution_time)
      _ -> Logger.info "Status update failed!"
    end
  end

  defp humanize_time(seconds) do
    Float.floor(seconds / 60)
  end

  defp ambiguous_handle(value) do
    case value do
      {:ok, datetime} -> datetime
      {:ambiguous, datetime} -> datetime.possible_date_times |> hd
    end
  end

  defp get_head_tail([]), do: []
  defp get_head_tail(nil), do: []
  defp get_head_tail([head|tail]) do
    [[head]|get_head_tail(tail)]
  end

  def count_download(start_end, interval, acc \\ 0)
  def count_download([], _interval, acc), do: acc
  def count_download([starting, ending], interval, acc) do
    count_loop(starting, ending, interval, acc)
  end

  defp count_loop(starting, ending, _interval, acc) when starting >= ending, do: acc
  defp count_loop(starting, ending, interval, acc) do
    count_loop(starting + interval, ending, interval, acc + 1)
  end

  def download([], _camera_exid, _interval, _id, _requestor), do: :noop
  def download([starting, ending], camera_exid, interval, id, requestor) do
    do_loop(starting, ending, interval, camera_exid, id, requestor)
  end

  defp do_loop(starting, ending, _interval, _camera_exid, _id, _requestor) when starting >= ending, do: :noop
  defp do_loop(starting, ending, interval, camera_exid, id, requestor) do
    %{year: year, month: month, day: day, hour: hour, min: min, sec: sec} = make_me_complete(starting)
    filer = point_to_seaweed(Calendar.DateTime.Parse.unix!(starting))
    url = "#{filer.url}/#{camera_exid}/snapshots/recordings/#{year}/#{month}/#{day}/#{hour}/#{min}_#{sec}_000.jpg"
    case HTTPoison.get(url, [], []) do
      {:ok, %HTTPoison.Response{body: body, status_code: 200}} ->
        upload(200, body, starting, camera_exid, id, requestor)
        image_name = Calendar.DateTime.Parse.unix!(starting) |> Calendar.DateTime.Format.rfc3339
        save_current_jpeg_time(image_name, "#{@root_dir}/#{camera_exid}/extract/#{id}/")
        do_loop(starting + interval, ending, interval, camera_exid, id, requestor)
      {:ok, %HTTPoison.Response{body: "", status_code: 404}} ->
        add_up = the_most_nearest("#{filer.url}/#{camera_exid}/snapshots/recordings/#{year}/#{month}/#{day}/#{hour}/?limit=3600", starting)
        do_loop(starting + add_up, ending, interval, camera_exid, id, requestor)
      {:error, %HTTPoison.Error{reason: _reason}} ->
        :timer.sleep(:timer.seconds(3))
        do_loop(starting, ending, interval, camera_exid, id, requestor)
    end
  end

  defp the_most_nearest(url, starting) do
    date_on = Calendar.DateTime.Parse.unix!(starting)
    %{year: _year, month: _month, day: _day, hour: _hour, min: min, sec: sec} = make_me_complete(starting)
    on_miss = "#{min}_#{sec}_000.jpg"
    filer = point_to_seaweed(date_on)

    request_from_seaweedfs(url, filer.files, filer.name)
    |> case do
      [] ->
        [r_min, r_sec, _] = String.split(on_miss, "_")
        r_second = Integer.parse(r_sec) |> elem(0)
        r_minute =  Integer.parse(r_min) |> elem(0)
        recent_secs = (r_minute * 60) + r_second
        3600 - recent_secs
      files ->
        files |> Enum.uniq |> Enum.sort |> Enum.filter(fn(file) -> file > on_miss end) |> List.first |> nearest_min_sec(on_miss)
    end
  end

  defp nearest_min_sec(nil, recent_file) do
    [r_min, r_sec, _] = String.split(recent_file, "_")
    r_second = Integer.parse(r_sec) |> elem(0)
    r_minute =  Integer.parse(r_min) |> elem(0)
    recent_secs = (r_minute * 60) + r_second
    3600 - recent_secs
  end
  defp nearest_min_sec(near_file, recent_file) do
    [n_min, n_sec, _] = String.split(near_file, "_")
    n_second = Integer.parse(n_sec) |> elem(0)
    n_minute =  Integer.parse(n_min) |> elem(0)
    [r_min, r_sec, _] = String.split(recent_file, "_")
    r_second = Integer.parse(r_sec) |> elem(0)
    r_minute =  Integer.parse(r_min) |> elem(0)
    near_secs = (n_minute * 60) + n_second
    recent_secs = (r_minute * 60) + r_second
    near_secs - recent_secs
  end

  def get_ending_hour(ending_hour, ending_minutes) do
    case ending_minutes > 0 do
      true -> ending_hour + 1
      false -> ending_hour
    end
  end

  def upload(200, response, starting, camera_exid, id, requestor) do
    construction =
      case requestor do
        "marklensmen@gmail.com" ->
          "Construction"
        _ ->
          "Construction2"
      end

    image_save_path = "#{@root_dir}/#{camera_exid}/extract/#{id}/#{starting}.jpg"
    path = "#{@root_dir}/#{camera_exid}/extract/#{id}/"
    File.write(image_save_path, response, [:binary]) |> File.close

    client = ElixirDropbox.Client.new(System.get_env["DROP_BOX_TOKEN"])
    {:ok, file_size} = get_file_size(image_save_path)

    try do
      %{"session_id" => session_id} = ElixirDropbox.Files.UploadSession.start(client, true, image_save_path)
      write_sessional_values(session_id, file_size, "/#{construction}/#{camera_exid}/#{id}/#{starting}.jpg", path)
      check_1000_chunk(path) |> length() |> commit_if_1000(client, path)
    rescue
      _ ->
        :timer.sleep(:timer.seconds(3))
        upload(200, response, starting, camera_exid, id, requestor)
    end
  end
  def upload(_, _response, _starting, _camera_exid, _id, _requestor), do: :noop

  defp find_difference(end_date, start_date) do
    case Calendar.DateTime.diff(end_date, start_date) do
      {:ok, seconds, _, :after} -> seconds
      _ -> 1
    end
  end

  def iterate([], _check_time, _timezone), do: []
  def iterate([head], check_time, timezone) do
    [from, to] = String.split head, "-"
    [from_hour, from_minute] = String.split from, ":"
    [to_hour, to_minute] = String.split to, ":"

    from_unix_timestamp = unix_timestamp(from_hour, from_minute, check_time, timezone)
    to_unix_timestamp = unix_timestamp(to_hour, to_minute, check_time, timezone)
    [from_unix_timestamp, to_unix_timestamp]
  end

  defp unix_timestamp(hours, minutes, date, nil) do
    unix_timestamp(hours, minutes, date, "UTC")
  end
  defp unix_timestamp(hours, minutes, date, timezone) do
    %{year: year, month: month, day: day} = date
    {h, _} = Integer.parse(hours)
    {m, _} = Integer.parse(minutes)
    erl_date_time = {{year, month, day}, {h, m, 0}}
    case Calendar.DateTime.from_erl(erl_date_time, timezone) do
      {:ok, datetime} -> datetime |> Calendar.DateTime.Format.unix
      {:ambiguous, datetime} -> datetime.possible_date_times |> hd |> Calendar.DateTime.Format.unix
      _ -> raise "Timezone conversion error"
    end
  end

  defp round_2(0), do: 2
  defp round_2(n), do: n + 1

  defp intervaling(0), do: 1
  defp intervaling(n), do: n

  defp send_mail_end(false, _full_extractor, _count, _expected_count, _execution_time), do: :noop
  defp send_mail_end(true, full_extractor, count, expected_count, execution_time), do: EvercamMedia.UserMailer.snapshot_extraction_completed(full_extractor, count, expected_count, execution_time)

  defp make_me_complete(date) do
    {{year, month, day}, {hour, min, sec}} = Calendar.DateTime.Parse.unix!(date) |> Calendar.DateTime.to_erl
    month = String.pad_leading("#{month}", 2, "0")
    day = String.pad_leading("#{day}", 2, "0")
    hour = String.pad_leading("#{hour}", 2, "0")
    min = String.pad_leading("#{min}", 2, "0")
    sec = String.pad_leading("#{sec}", 2, "0")
    %{year: year, month: month, day: day, hour: hour, min: min, sec: sec}
  end

  defp ensure_a_day(date, url) do
    filer = point_to_seaweed(date)
    day = Calendar.Strftime.strftime!(date, "%Y/%m/%d/")
    url_day = url <> "#{day}"
    case request_from_seaweedfs(url_day, filer.type, filer.attribute) |> Enum.empty? do
      true -> :not_ok
      false -> :ok
    end
  end
end
