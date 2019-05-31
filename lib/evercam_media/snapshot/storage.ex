defmodule EvercamMedia.Snapshot.Storage do
  require Logger
  alias EvercamMedia.Util
  import EvercamMedia.TimelapseRecording.S3, only: [do_save: 3, do_load: 1]

  @root_dir Application.get_env(:evercam_media, :storage_dir)
  @seaweedfs Application.get_env(:evercam_media, :seaweedfs_url)
  @seaweedfs_1 Application.get_env(:evercam_media, :seaweedfs_url_1)
  @seaweedfs_new Application.get_env(:evercam_media, :seaweedfs_url_new)

  def point_to_seaweed(request_date) do
    oct_date =
      {{2017, 10, 31}, {23, 59, 59}}
      |> Calendar.DateTime.from_erl!("UTC")

    case Calendar.DateTime.diff(request_date, oct_date) do
      {:ok, secs, _, :after} ->
        case secs > 31536000 do
          true -> @seaweedfs_new
          false -> @seaweedfs
        end
      _ -> @seaweedfs_1
    end
  end

  def latest(camera_exid) do
    Path.wildcard("#{@root_dir}/#{camera_exid}/snapshots/*")
    |> Enum.reject(fn(x) -> String.match?(x, ~r/thumbnail.jpg/) end)
    |> Enum.reduce("", fn(type, acc) ->
      year = Path.wildcard("#{type}/????/") |> List.last
      month = Path.wildcard("#{year}/??/") |> List.last
      day = Path.wildcard("#{month}/??/") |> List.last
      hour = Path.wildcard("#{day}/??/") |> List.last
      last = Path.wildcard("#{hour}/??_??_???.jpg") |> List.last
      Enum.max_by([acc, "#{last}"], fn(x) -> String.slice(x, -27, 27) end)
    end)
  end

  # Temporary solution for extractor to sync
  def seaweedfs_save_sync(camera_exid, timestamp, image, _notes) do
    seaweedfs = timestamp |> Calendar.DateTime.Parse.unix! |> point_to_seaweed
    hackney = [pool: :seaweedfs_upload_pool]
    directory_path = construct_directory_path(camera_exid, timestamp, "recordings", "")
    file_name = construct_file_name(timestamp)
    file_path = directory_path <> file_name
    case HTTPoison.post("#{seaweedfs}#{file_path}", {:multipart, [{file_path, image, []}]}, [], hackney: hackney) do
      {:ok, response} -> response
      {:error, error} -> Logger.info "[seaweedfs_save_sync] [#{camera_exid}] [#{inspect error}]"
    end
  end

  def seaweedfs_save(camera_exid, timestamp, image, _notes) do
    hackney = [pool: :seaweedfs_upload_pool]
    directory_path = construct_directory_path(camera_exid, timestamp, "recordings", "")
    file_name = construct_file_name(timestamp)
    file_path = directory_path <> file_name
    case HTTPoison.post("#{@seaweedfs_new}#{file_path}", {:multipart, [{file_path, image, []}]}, [], hackney: hackney) do
      {:ok, response} -> response
      {:error, error} -> Logger.info "[seaweedfs_save] [#{camera_exid}] [#{inspect error}]"
    end
  end

  def seaweedfs_thumbnail_export(file_path, image) do
    path = String.replace_leading(file_path, "/storage", "")
    hackney = [pool: :seaweedfs_upload_pool]
    url = "#{@seaweedfs}#{path}"
    case HTTPoison.head(url, [], hackney: hackney) do
      {:ok, %HTTPoison.Response{status_code: 200}} ->
        HTTPoison.put!(url, {:multipart, [{path, image, []}]}, [], hackney: hackney)
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        HTTPoison.post!(url, {:multipart, [{path, image, []}]}, [], hackney: hackney)
      error ->
        raise "Upload for file path '#{file_path}' failed with: #{inspect error}"
    end
  end

  def exists_for_day?(camera_exid, from, to, timezone) do
    hours = hours(camera_exid, from, to, timezone)
    !Enum.empty?(hours)
  end

  def nearest(camera_exid, timestamp, version \\ :v1, timezone \\ "UTC") do
    parse_timestamp = timestamp |> Calendar.DateTime.Parse.unix!
    list_of_snapshots =
      camera_exid
      |> get_camera_apps_list(parse_timestamp)
      |> Enum.flat_map(fn(app) -> do_seaweedfs_load_range(camera_exid, timestamp, app) end)
      |> Enum.sort_by(fn(snapshot) -> snapshot.created_at end)

    with nil <- get_snapshot("timestamp", list_of_snapshots, timestamp),
         nil <- get_snapshot("after", list_of_snapshots, timestamp),
         nil <- get_snapshot("before", list_of_snapshots, timestamp) do
      []
    else
      snapshot ->
        {:ok, image, _notes} = load(camera_exid, snapshot.created_at, snapshot.notes)
        data = "data:image/jpeg;base64,#{Base.encode64(image)}"
        case version do
          :v1 -> [%{created_at: snapshot.created_at, notes: snapshot.notes, data: data}]
          :v2 -> [%{created_at: Util.convert_unix_to_iso(snapshot.created_at, timezone), notes: snapshot.notes, data: data}]
        end
    end
  end

  defp get_snapshot("timestamp", snapshots, timestamp) do
    snapshots
    |> Enum.filter(fn(snapshot) -> snapshot.created_at == timestamp end)
    |> List.first
  end
  defp get_snapshot("after", snapshots, timestamp) do
    from_date = parse_timestamp(timestamp)
    snapshots
    |> Enum.reject(fn(snapshot) -> is_before_to?(parse_timestamp(snapshot.created_at), from_date) end)
    |> List.first
  end
  defp get_snapshot("before", snapshots, timestamp) do
    from_date = parse_timestamp(timestamp)
    snapshots
    |> Enum.reject(fn(snapshot) -> is_after_from?(parse_timestamp(snapshot.created_at), from_date) end)
    |> List.last
  end

  defp seaweefs_type(@seaweedfs_new), do: "Entries"
  defp seaweefs_type(_), do: "Directories"

  defp seaweedfs_attribute(@seaweedfs_new), do: "FullPath"
  defp seaweedfs_attribute(_), do: "Name"

  defp seaweedfs_files(@seaweedfs_new), do: "Entries"
  defp seaweedfs_files(_), do: "Files"

  defp seaweedfs_name(@seaweedfs_new), do: "FullPath"
  defp seaweedfs_name(_), do: "name"

  def days(camera_exid, from, to, timezone) do
    seaweedfs = point_to_seaweed(from)
    type = seaweefs_type(seaweedfs)
    attribute = seaweedfs_attribute(seaweedfs)
    url_base = "#{seaweedfs}/#{camera_exid}/snapshots"
    apps_list = get_camera_apps_list(camera_exid, from)
    from_date = Calendar.Strftime.strftime!(from, "%Y/%m")
    to_date = Calendar.Strftime.strftime!(to, "%Y/%m")

    from_days =
      apps_list
      |> Enum.flat_map(fn(app) -> request_from_seaweedfs("#{url_base}/#{app}/#{from_date}/", type, attribute) end)
      |> Enum.uniq
      |> Enum.map(fn(day) -> parse_day(from.year, from.month, day, timezone) end)
      |> Enum.reject(fn(datetime) -> Calendar.DateTime.before?(datetime, from) end)

    seaweedfs = point_to_seaweed(to)
    type = seaweefs_type(seaweedfs)
    attribute = seaweedfs_attribute(seaweedfs)
    url_base = "#{seaweedfs}/#{camera_exid}/snapshots"
    to_days =
      apps_list
      |> Enum.flat_map(fn(app) -> request_from_seaweedfs("#{url_base}/#{app}/#{to_date}/", type, attribute) end)
      |> Enum.uniq
      |> Enum.map(fn(day) -> parse_day(to.year, to.month, day, timezone) end)
      |> Enum.reject(fn(datetime) -> Calendar.DateTime.after?(datetime, to) end)

    Enum.concat(from_days, to_days)
    |> Enum.map(fn(datetime) -> datetime.day end)
    |> Enum.sort
    |> Enum.uniq
  end

  def hours(camera_exid, from, to, timezone) do
    seaweedfs = point_to_seaweed(from)
    type = seaweefs_type(seaweedfs)
    attribute = seaweedfs_attribute(seaweedfs)
    url_base = "#{seaweedfs}/#{camera_exid}/snapshots"
    apps_list = get_camera_apps_list(camera_exid, from)
    from_date = Calendar.Strftime.strftime!(from, "%Y/%m/%d")
    to_date = Calendar.Strftime.strftime!(to, "%Y/%m/%d")

    from_hours =
      apps_list
      |> Enum.flat_map(fn(app) -> request_from_seaweedfs("#{url_base}/#{app}/#{from_date}/", type, attribute) end)
      |> Enum.uniq
      |> Enum.map(fn(hour) -> parse_hour(from.year, from.month, from.day, "#{hour}:00:00", timezone) end)
      |> Enum.reject(fn(datetime) -> Calendar.DateTime.before?(datetime, from) end)

    seaweedfs = point_to_seaweed(to)
    type = seaweefs_type(seaweedfs)
    attribute = seaweedfs_attribute(seaweedfs)
    url_base = "#{seaweedfs}/#{camera_exid}/snapshots"
    to_hours =
      apps_list
      |> Enum.flat_map(fn(app) -> request_from_seaweedfs("#{url_base}/#{app}/#{to_date}/", type, attribute) end)
      |> Enum.uniq
      |> Enum.map(fn(hour) -> parse_hour(to.year, to.month, to.day, "#{hour}:00:00", timezone) end)
      |> Enum.reject(fn(datetime) -> Calendar.DateTime.after?(datetime, to) end)

    Enum.concat(from_hours, to_hours)
    |> Enum.map(fn(datetime) -> datetime.hour end)
    |> Enum.sort
    |> Enum.uniq
  end

  def hour(camera_exid, hour, version \\ :v1, timezone \\ "UTC") do
    seaweedfs = point_to_seaweed(hour)
    files = seaweedfs_files(seaweedfs)
    name = seaweedfs_name(seaweedfs)
    url_base = "#{seaweedfs}/#{camera_exid}/snapshots"
    apps_list = get_camera_apps_list(camera_exid, hour)
    hour_datetime = Calendar.Strftime.strftime!(hour, "%Y/%m/%d/%H")
    dir_paths = lookup_dir_paths(camera_exid, apps_list, hour)

    apps_list
    |> Enum.map(fn(app_name) ->
      {app_name, request_from_seaweedfs("#{url_base}/#{app_name}/#{hour_datetime}/?limit=3600", files, name)}
    end)
    |> Enum.reject(fn({_app_name, files}) -> files == [] end)
    |> Enum.flat_map(fn({app_name, files}) ->

      files
      |> Enum.reject(fn(file_name) -> file_name == "metadata.json" end)
      |> Enum.reject(fn(file_name) -> String.ends_with?(file_name, ".json") end)
      |> Enum.map(fn(file_name) ->
        Map.get(dir_paths, app_name)
        |> construct_snapshot_record(file_name, app_name, 0, version, timezone)
      end)
    end)
  end

  def seaweedfs_load_range(camera_exid, from, to, version \\ :v1, timezone \\ "UTC") do
    from_date = parse_timestamp(from)
    to_date = parse_timestamp(to)

    camera_exid
    |> get_camera_apps_list(from_date)
    |> Enum.flat_map(fn(app) -> do_seaweedfs_load_range(camera_exid, from, app, version, timezone) end)
    |> Enum.reject(fn(snapshot) -> not_is_between?(snapshot.created_at, from_date, to_date) end)
    |> Enum.sort_by(fn(snapshot) -> snapshot.created_at end)
  end

  defp do_seaweedfs_load_range(camera_exid, from, app_name, version \\ :v1, timezone \\ "UTC") do
    storage_url =
      from
      |> parse_timestamp
      |> point_to_seaweed

    directory_path = construct_directory_path(camera_exid, from, app_name, "")
    files = seaweedfs_files(storage_url)
    name = seaweedfs_name(storage_url)

    request_from_seaweedfs("#{storage_url}#{directory_path}?limit=3600", files, name)
    |> Enum.reject(fn(file_name) -> file_name == "metadata.json" end)
    |> Enum.map(fn(file_name) ->
      construct_snapshot_record(directory_path, file_name, app_name, 0, version, timezone)
    end)
  end

  defp get_camera_apps_list(_, request_date \\ nil)
  defp get_camera_apps_list(_, nil) do
    ["recordings", "archives"]
  end
  defp get_camera_apps_list(_, request_date) do
    case point_to_seaweed(request_date) do
      base_url when base_url == @seaweedfs_1 ->
        ["timelapse", "recordings", "archives"]
      _ ->
        ["recordings", "archives"]
    end
  end

  def request_from_seaweedfs(url, type, attribute) do
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 15000]
    with {:ok, response} <- HTTPoison.get(url, ["Accept": "application/json"], hackney: hackney),
         %HTTPoison.Response{status_code: 200, body: body} <- response,
         {:ok, data} <- Poison.decode(body),
         true <- is_list(data[type]) do
      Enum.map(data[type], fn(item) -> item[attribute] |> get_base_name(type, attribute) end)
    else
      _ -> []
    end
  end

  defp get_base_name(list, "Entries", "FullPath"), do: list |> Path.basename
  defp get_base_name(list, _, _), do: list

  def thumbnail_load(camera_exid) do
    seaweed_thumbnail_load(camera_exid)
  end

  def seaweed_thumbnail_load(camera_exid) do
    url = "#{@seaweedfs_new}/#{camera_exid}/snapshots/thumbnail.jpg"
    case ConCache.get(:camera_thumbnail, camera_exid) do
      nil ->
        case HTTPoison.get(url, [], hackney: [pool: :seaweedfs_download_pool]) do
          {:ok, %HTTPoison.Response{status_code: 200, body: snapshot, headers: header}} ->
            {_, last_modified_date} = List.keyfind(header, "Last-Modified", 0)
            thumbnail_timestamp =
              last_modified_date
              |> Timex.parse!("{RFC1123}")
              |> Timex.format!("{ISO:Extended:Z}")
              |> Calendar.DateTime.Parse.rfc3339_utc
              |> elem(1)
              |> Calendar.DateTime.Format.unix
            ConCache.put(:camera_thumbnail, camera_exid, {Calendar.DateTime.now!("UTC"), thumbnail_timestamp, snapshot})
            {:ok, thumbnail_timestamp, snapshot}
          _error -> {:error, Util.unavailable}
        end
      {_last_save_date, timestamp, img} -> {:ok, timestamp, img}
    end
  end

  def import_thumbnail_from_old_server() do
    Camera.all |> Enum.each(fn(c) ->
      nov_url = "#{@seaweedfs_new}/#{c.exid}/snapshots/thumbnail.jpg"
      oct_url = "#{@seaweedfs}/#{c.exid}/snapshots/thumbnail.jpg"
      case HTTPoison.get(nov_url, [], hackney: [pool: :seaweedfs_download_pool]) do
        {:ok, %HTTPoison.Response{status_code: 200, body: _snapshot, headers: _header}} ->
          Logger.info "Alreday have latest thumbnail of camera: #{c.exid}"
        _error ->
          case HTTPoison.get(oct_url, [], hackney: [pool: :seaweedfs_download_pool]) do
            {:ok, %HTTPoison.Response{status_code: 200, body: snapshot, headers: _header}} ->
              Logger.info "Save thumbnail from oct server. Camera: #{c.exid}"
              file_path = "/#{c.exid}/snapshots/thumbnail.jpg"
              case HTTPoison.post(nov_url, {:multipart, [{file_path, snapshot, []}]}, [], hackney: [pool: :seaweedfs_upload_pool]) do
                {:ok, _} -> :noop
                {:error, error} -> Logger.info "[thumbnail_import_error] [#{c.exid}] [#{inspect error}]"
              end
            _error -> Logger.info "No thumbnail."
          end
      end
    end)
  end

  def import_oldest_from_old_server() do
    Camera.all |> Enum.each(fn(c) ->
      oldest_image_name =
        "#{@seaweedfs}/#{c.exid}/snapshots/?limit=1"
        |> request_from_seaweedfs("Files", "name")
        |> Enum.sort(&(&2 > &1))
        |> List.first

      case oldest_image_name  do
        nil -> Logger.info "No image found for camera: #{c.exid}"
        file_id when file_id == "thumbnail.jpg" -> Logger.info "Found thumbnail for camera: #{c.exid}"
        _ ->
          Logger.info "Oldest image found for camera: #{c.exid}, image: #{oldest_image_name}"
          oct_url = "#{@seaweedfs}/#{c.exid}/snapshots/#{oldest_image_name}"
          case HTTPoison.get(oct_url, [], hackney: [pool: :seaweedfs_download_pool]) do
            {:ok, %HTTPoison.Response{status_code: 200, body: snapshot}} ->
              nov_url = "#{@seaweedfs_new}/#{c.exid}/snapshots/#{oldest_image_name}"
              file_path = "/#{c.exid}/snapshots/#{oldest_image_name}"
              case HTTPoison.post(nov_url, {:multipart, [{file_path, snapshot, []}]}, [], hackney: [pool: :seaweedfs_upload_pool]) do
                {:ok, _} -> Logger.info "Save oldest image for camera: #{c.exid}, #{nov_url}"
                {:error, error} -> Logger.info "[import_oldest_from_old_server] [#{c.exid}] [#{inspect error}]"
              end
            _error ->
              Logger.info "Failed to get oldest snapshot for camera: #{c.exid}"
          end
      end
    end)
  end

  def disk_thumbnail_load(camera_exid) do
    "#{@root_dir}/#{camera_exid}/snapshots/thumbnail.jpg"
    |> File.open([:read, :binary, :raw], fn(file) -> IO.binread(file, :all) end)
    |> case do
      {:ok, content} -> {:ok, content}
      {:error, _error} -> {:error, Util.unavailable}
    end
  end

  def thumbnail_options(camera_exid) do
    hackney = [pool: :seaweedfs_upload_pool]
    url = "#{@seaweedfs}/#{camera_exid}/snapshots/thumbnail.jpg"
    case HTTPoison.head(url, [], hackney: hackney) do
      {:ok, %HTTPoison.Response{headers: head, status_code: 200}} -> {:ok, head}
      error ->
        Logger.debug "Upload for file path '#{url}' failed with: #{inspect error}"
    end
  end

  def copy_oldest_image(camera_exid, source, erl_date) do
    {:ok, datetime} = Calendar.DateTime.from_erl(erl_date, "UTC")
    unix_timestamp =  datetime |> Calendar.DateTime.Format.unix
    case HTTPoison.get(source, [], hackney: [pool: :seaweedfs_download_pool]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: snapshot}} ->
        save_oldest_snapshot(camera_exid, snapshot, unix_timestamp)
        {:ok}
      _error -> {:error}
    end
  end

  ########################################
  ###### Load latest image to cache ######
  ########################################
  def check_camera_last_image(camera_id) do
    Logger.info "Load thumbnail to cache."
    with {:error, _} <- load_latest_snapshot_to_cache(@seaweedfs_new, "#{camera_id}/snapshots/recordings"),
         {:error, _} <- load_latest_snapshot_to_cache(@seaweedfs_new, "#{camera_id}/snapshots/archives"),
         {:error, _} <- load_latest_snapshot_to_cache(@seaweedfs_1, "#{camera_id}/snapshots/recordings"),
         {:error, _} <- load_latest_snapshot_to_cache(@seaweedfs_1, "#{camera_id}/snapshots/archives"),
         {:error, _} <- load_latest_snapshot_to_cache(@seaweedfs, "#{camera_id}/snapshots/recordings"),
         {:error, _} <- load_latest_snapshot_to_cache(@seaweedfs, "#{camera_id}/snapshots/archives"),
         {:error, _} <- load_latest_snapshot_to_cache(@seaweedfs, "#{camera_id}/snapshots/timelapse") do
    else
      {:ok, image, timestamp} -> update_cache_thumbnail("#{camera_id}", timestamp, image)
    end
  end

  defp load_latest_snapshot_to_cache(weed_url, path) do
    hackney = [pool: :seaweedfs_download_pool]
    type = seaweefs_type(weed_url)
    attribute = seaweedfs_attribute(weed_url)
    files = seaweedfs_files(weed_url)
    name = seaweedfs_name(weed_url)

    with {:year, year} <- get_latest_directory_name(:year, "#{weed_url}/#{path}/", type, attribute),
         {:month, month} <- get_latest_directory_name(:month, "#{weed_url}/#{path}/#{year}/", type, attribute),
         {:day, day} <- get_latest_directory_name(:day, "#{weed_url}/#{path}/#{year}/#{month}/", type, attribute),
         {:hour, hour} <- get_latest_directory_name(:hour, "#{weed_url}/#{path}/#{year}/#{month}/#{day}/", type, attribute),
         {:image, last_image} <- get_latest_directory_name(:image, "#{weed_url}/#{path}/#{year}/#{month}/#{day}/#{hour}/?limit=3600", files, name) do
      case HTTPoison.get("#{weed_url}/#{path}/#{year}/#{month}/#{day}/#{hour}/#{last_image}", [], hackney: hackney) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          [minute, second, _] = String.split(last_image, "_")
          erl_date = {{to_integer(year), to_integer(month), to_integer(day)}, {to_integer(hour), to_integer(minute), to_integer(second)}}
          {:ok, datetime} = Calendar.DateTime.from_erl(erl_date, "UTC")
          {:ok, body, datetime |> Calendar.DateTime.Format.unix}
        {:ok, %HTTPoison.Response{status_code: 404}} -> {:error, "not found"}
        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, reason}
      end
    else
      _ -> {:error, "Not Found."}
    end
  end

  defp get_latest_directory_name(directory, url, type, attribute) do
    request_from_seaweedfs(url, type, attribute)
    |> Enum.sort
    |> case do
      [] -> {:error}
      res -> {directory, List.last(res)}
    end
  end
  ############################################
  ###### End load latest image to cache ######
  ############################################

  ##########################
  ###### Oldest Image ######
  ##########################
  def get_or_save_oldest_snapshot(camera_exid) do
    "#{@seaweedfs_new}/#{camera_exid}/snapshots/"
    |> request_from_seaweedfs("Entries", "FullPath")
    |> Enum.map(fn dir ->
      is_oldest?(dir)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort(&(&2 > &1))
    |> List.first
    |> load_oldest_snapshot(camera_exid)
  end

  defp is_oldest?(<<"oldest-", _::binary>> = dir), do: dir
  defp is_oldest?(_), do: nil

  def load_oldest_snapshot(<<"oldest-", _::binary>> = file_name, camera_exid) do
    url = "#{@seaweedfs_new}/#{camera_exid}/snapshots/"
    case HTTPoison.get("#{url}#{file_name}", [], hackney: [pool: :seaweedfs_download_pool]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: snapshot}} ->
        {:ok, snapshot, take_prefix(file_name, "oldest-")}
      _error ->
        import_oldest_image(camera_exid)
    end
  end
  def load_oldest_snapshot(_file_name, camera_exid) do
    import_oldest_image(camera_exid)
  end

  def take_prefix(full, prefix) do
    base = String.length(prefix)
    String.slice(full, base..-5)
  end

  def import_oldest_image(camera_exid) do
    url = "#{@seaweedfs_new}/#{camera_exid}/snapshots/"
    {{year, month, day}, {h, _m, _s}} = Calendar.DateTime.now_utc |> Calendar.DateTime.to_erl

    {snapshot, _error, _datetime} =
      request_from_seaweedfs(url, "Entries", "FullPath")
      |> Enum.reduce({{}, {}, {year, month, day, h}}, fn(note, {snapshot, error, datetime}) ->
        {yr, mh, dy, hr} = datetime
        case get_oldest_snapshot(url, note, yr, mh, dy, hr) do
          {:ok, image, datetime, y, m, d, h} ->
            {{:ok, image, datetime}, error, {y, m, d, h}}
          {:error, message, y, m, d, h} ->
            {snapshot, {:error, message}, {y, m, d, h}}
        end
      end)
    case snapshot do
      {} -> {:error, "Oldest image does not exist."}
      {:ok, image, datetime} ->
        spawn fn -> save_oldest_snapshot(camera_exid, image, datetime) end
        {:ok, image, datetime}
    end
  end

  def save_oldest_snapshot(camera_exid, image, datetime) do
    hackney = [pool: :seaweedfs_upload_pool]
    url = "#{@seaweedfs_new}/#{camera_exid}/snapshots/oldest-#{datetime}.jpg"
    file_path = "/#{camera_exid}/snapshots/oldest-#{datetime}.jpg"
    case HTTPoison.post(url, {:multipart, [{file_path, image, []}]}, [], hackney: hackney) do
      {:ok, response} -> response
      {:error, error} -> Logger.info "[save_oldest_snapshot] [#{camera_exid}] [#{inspect error}]"
    end
  end

  defp get_oldest_snapshot(url, note, syear, smonth, sday, shour) do
    hackney = [pool: :seaweedfs_download_pool]
    date2 = {{syear, smonth, sday}, {shour, 0, 0}}
    with {:year, year} <- get_oldest_directory_name(:year, "#{url}#{note}/"),
         true <- is_previous_date({{to_integer(year), 1, 1}, {0, 0, 0}}, date2, year),
         {:month, month} <- get_oldest_directory_name(:month, "#{url}#{note}/#{year}/"),
         true <- is_previous_date({{to_integer(year), to_integer(month), 1}, {0, 0, 0}}, date2, month),
         {:day, day} <- get_oldest_directory_name(:day, "#{url}#{note}/#{year}/#{month}/"),
         true <- is_previous_date({{to_integer(year), to_integer(month), to_integer(day)}, {0, 0, 0}}, date2, day),
         {:hour, hour} <- get_oldest_directory_name(:hour, "#{url}#{note}/#{year}/#{month}/#{day}/"),
         true <- is_previous_date({{to_integer(year), to_integer(month), to_integer(day)}, {to_integer(hour), 0, 0}}, date2, hour),
         {:image, oldest_image} <- get_oldest_directory_name(:image, "#{url}#{note}/#{year}/#{month}/#{day}/#{hour}/?limit=2", "Entries", "FullPath") do
      case HTTPoison.get("#{url}#{note}/#{year}/#{month}/#{day}/#{hour}/#{oldest_image}", [], hackney: hackney) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          [minute, second, _] = String.split(oldest_image, "_")
          erl_date = {{to_integer(year), to_integer(month), to_integer(day)}, {to_integer(hour), to_integer(minute), to_integer(second)}}
          {:ok, datetime} = Calendar.DateTime.from_erl(erl_date, "UTC")
          {:ok, body, datetime |> Calendar.DateTime.Format.unix, to_integer(year), to_integer(month), to_integer(day), to_integer(hour)}
        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, reason, syear, smonth, sday, shour}
      end
    else
      _ -> {:error, "Not Found.", syear, smonth, sday, shour}
    end
  end

  defp get_oldest_directory_name(directory, url, type \\ "Entries", attribute \\ "FullPath") do
    {
      directory,
      request_from_seaweedfs(url, type, attribute)
      |> Enum.sort(&(&2 > &1))
      |> List.first
    }
  end

  defp is_previous_date(_date1, _date2, number) when number in [nil, ""], do: false
  defp is_previous_date(date1, date2, _number) do
    d1 = Calendar.DateTime.from_erl!(date1, "UTC")
    d2 = Calendar.DateTime.from_erl!(date2, "UTC")
    case Calendar.DateTime.diff(d2, d1) do
      {:ok, _, _, :before} -> false
      {:ok, _, _, :after} -> true
      {:ok, _, _, :same_time} -> true
    end
  end

  def oldest_snapshot(camera_exid, cloud_recording) do
    url = "#{@seaweedfs}/#{camera_exid}/snapshots/"
    hackney = [pool: :seaweedfs_download_pool]
    with {:notes, notes} <- oldest_directory_name(cloud_recording, :notes, url),
         {:year, year} <- oldest_directory_name(cloud_recording, :year, "#{url}#{notes}/"),
         {:month, month} <- oldest_directory_name(cloud_recording, :month, "#{url}#{notes}/#{year}/"),
         {:day, day} <- oldest_directory_name(cloud_recording, :day, "#{url}#{notes}/#{year}/#{month}/"),
         {:hour, hour} <- oldest_directory_name(cloud_recording, :hour, "#{url}#{notes}/#{year}/#{month}/#{day}/"),
         {:image, oldest_image} <- oldest_directory_name(cloud_recording, :image, "#{url}#{notes}/#{year}/#{month}/#{day}/#{hour}/?limit=3600", "Files", "name") do
      case HTTPoison.get("#{url}#{notes}/#{year}/#{month}/#{day}/#{hour}/#{oldest_image}", [], hackney: hackney) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          [minute, second, _] = String.split(oldest_image, "_")
          erl_date = {{to_integer(year), to_integer(month), to_integer(day)}, {to_integer(hour), to_integer(minute), to_integer(second)}}
          {:ok, datetime} = Calendar.DateTime.from_erl(erl_date, "UTC")
          {:ok, body, datetime |> Calendar.DateTime.Format.unix}
        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, reason}
      end
    else
      _ -> {:error, "Not Found."}
    end
  end

  ##########################
  #### End oldest Image ####
  ##########################

  defp to_integer(nil), do: ""
  defp to_integer(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> :error
    end
  end

  def save(camera_exid, timestamp, image, "Evercam SnapMail") do
    save_snapmail_to_s3("#{camera_exid}", timestamp, image)
    update_cache_thumbnail("#{camera_exid}", timestamp, image)
  end
  def save(camera_exid, timestamp, image, notes) do
    try do
      seaweedfs_save("#{camera_exid}", timestamp, image, notes)
      update_cache_thumbnail("#{camera_exid}", timestamp, image, Calendar.DateTime.now!("UTC"))
    catch _type, _error ->
      :noop
    end
  end

  defp save_snapmail_to_s3(camera_exid, timestamp, image) do
    path =
      timestamp
      |> Calendar.DateTime.Parse.unix!
      |> Calendar.Strftime.strftime!("#{camera_exid}/snapmails/%Y/%m/%d/%H/")

    filename = construct_file_name(timestamp)
    do_save("#{path}#{filename}", image, [content_type: "image/jpeg"])
  end

  defp oldest_directory_name(cloud_recording, directory, url, type \\ "Directories", attribute \\ "Name")
  defp oldest_directory_name(%CloudRecording{storage_duration: -1}, directory, url, type, attribute) do
    {structure, attr} =
      case directory do
        :hour -> {"Files", "name"}
        _ -> {type, attribute}
      end
    value =
      request_from_seaweedfs(url, type, attribute)
      |> Enum.sort(&(&2 > &1))
      |> exist_oldest_directory(directory, String.match?(url, ~r/archives/), url, structure, attr)
    {directory, value}
  end
  defp oldest_directory_name(_cloud_recording, directory, url, type, attribute) do
    {
      directory,
      request_from_seaweedfs(url, type, attribute)
      |> Enum.filter(fn(d) -> d != "recordings" end)
      |> Enum.sort(&(&2 > &1))
      |> List.first
    }
  end

  defp exist_oldest_directory([tail | _head], _directory, true, _url, _type, _attribute), do: tail
  defp exist_oldest_directory([tail | _head], :image, _bool, _url, _type, _attribute), do: tail
  defp exist_oldest_directory([tail | head], directory, bool, url, type, attribute) do
    case request_from_seaweedfs("#{url}#{tail}/", type, attribute) do
      [] -> exist_oldest_directory(head, directory, bool, url, type, attribute)
      _response -> tail
    end
  end
  defp exist_oldest_directory([], _directory, _bool, _url, _type, _attribute), do: :noop

  def update_cache_thumbnail(camera_exid, timestamp, image, thumbnail_save_date \\ nil) do
    {last_save_date, _, _img} = ConCache.dirty_get_or_store(:camera_thumbnail, camera_exid, fn() ->
      {Calendar.DateTime.now!("UTC"), timestamp, image}
    end)
    new_save_date =
      case thumbnail_save_date do
        nil -> last_save_date
        datetime -> datetime
      end
    ConCache.dirty_put(:camera_thumbnail, camera_exid, {new_save_date, timestamp, image})
  end

  def load_archive_thumbnail(camera_exid, archive_id) do
    file_path = "#{camera_exid}/clips/#{archive_id}/thumb-#{archive_id}.jpg"

    case do_load(file_path) do
      {:ok, body} -> body
      {:error, _code, _error} -> Util.default_thumbnail
    end
  end

  def save_archive_thumbnail(camera_exid, archive_id, path) do
    file_path = "#{camera_exid}/clips/#{archive_id}/thumb-#{archive_id}.jpg"

    "#{path}thumb-#{archive_id}.jpg"
    |> File.open([:read, :binary, :raw], fn(file) -> IO.binread(file, :all) end)
    |> case do
      {:ok, content} ->
        do_save(file_path, content, [content_type: "image/jpeg"])
      {:error, _error} -> {:error, "Failed to read video file."}
    end
  end

  def save_archive_file(camera_exid, archive_id, url, extension) do
    case HTTPoison.get("#{url}", [], hackney: [pool: :seaweedfs_download_pool]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: content}} ->
        file_path = "#{camera_exid}/clips/#{archive_id}/#{archive_id}.#{extension}"
        File.mkdir_p("#{@root_dir}/#{archive_id}/")
        File.write("#{@root_dir}/#{archive_id}/#{archive_id}.#{extension}", content)
        do_save(file_path, content, [content_type: "application/octet-stream"])
      {:error, _} -> :noop
    end
  end

  def save_archive_edited_image(camera_exid, archive_exid, content) do
    File.mkdir_p("#{@root_dir}/#{archive_exid}/")
    File.write("#{@root_dir}/#{archive_exid}/#{archive_exid}.png", content)
    file_path = "#{camera_exid}/clips/#{archive_exid}/#{archive_exid}.png"
    do_save(file_path, content, [content_type: "application/octet-stream"])
  end

  def save_mp4(camera_exid, archive_id, path) do
    "#{path}/#{archive_id}.mp4"
    |> File.open([:read, :binary, :raw], fn(file) -> IO.binread(file, :all) end)
    |> case do
      {:ok, content} -> seaweedfs_save_video_file(camera_exid, archive_id, content)
      {:error, _error} -> {:error, "Failed to read video file."}
    end
  end

  def seaweedfs_save_video_file(camera_exid, archive_id, content) do
    file_path = "#{camera_exid}/clips/#{archive_id}/#{archive_id}.mp4"
    do_save(file_path, content, [content_type: "video/mp4"])
  end

  def delete_archive(camera_exid, archive_id) do
    archive_path = "#{camera_exid}/clips/#{archive_id}/#{archive_id}.mp4"
    archive_thumbail_path = "#{camera_exid}/clips/#{archive_id}/thumb-#{archive_id}.jpg"
    Logger.info "[#{camera_exid}] [archive_delete] [#{archive_id}]"
    EvercamMedia.TimelapseRecording.S3.delete_object(["#{archive_path}", "#{archive_thumbail_path}"])
    Logger.info "[archive_delete] [#{camera_exid}] [#{archive_id}]"
  end

  def load(camera_exid, timestamp, notes) when notes in [nil, ""] do
    with {:error, _error} <- load(camera_exid, timestamp, "Evercam Proxy"),
         {:error, _error} <- load(camera_exid, timestamp, "Archives"),
         {:error, _error} <- load(camera_exid, timestamp, "Evercam Timelapse"),
         {:error, _error} <- load(camera_exid, timestamp, "Evercam SnapMail"),
         {:error, error} <- load(camera_exid, timestamp, "Evercam Thumbnail") do
      {:error, error}
    else
      {:ok, image, _notes} -> {:ok, image, ""}
    end
  end
  def load(camera_exid, timestamp, "Evercam SnapMail" = notes) do
    file_name = construct_file_name(timestamp)
    path =
      timestamp
      |> Calendar.DateTime.Parse.unix!
      |> Calendar.Strftime.strftime!("#{camera_exid}/snapmails/%Y/%m/%d/%H/")

    case do_load("#{path}#{file_name}") do
      {:ok, snapshot} -> {:ok, snapshot, notes}
      {:error, _code, _message} -> {:error, :not_found}
    end
  end
  def load(camera_exid, timestamp, notes) do
    img_datetime = Calendar.DateTime.Parse.unix!(timestamp)
    app_name = notes_to_app_name(notes)
    directory_path = construct_directory_path(camera_exid, timestamp, app_name, "")
    file_name = construct_file_name(timestamp)
    url = point_to_seaweed(img_datetime) <> directory_path <> file_name

    case HTTPoison.get(url, [], hackney: [pool: :seaweedfs_download_pool]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: snapshot}} ->
        {:ok, snapshot, notes}
      _error ->
        {:error, :not_found}
    end
  end

  def delete_jpegs_with_timestamps(timestamps, camera_exid) do
    Enum.each(timestamps, fn(timestamp) ->
      url =
        timestamp
        |> parse_timestamp
        |> point_to_seaweed
        |> create_jpeg_url(timestamp, camera_exid)
      spawn fn ->
        hackney = [pool: :seaweedfs_download_pool, recv_timeout: 30_000]
        HTTPoison.delete!("#{url}?recursive=true", [], hackney: hackney)
      end
    end)
  end

  defp create_jpeg_url(seaweedfs, timestamp, camera_exid) do
    directory_path =
      timestamp
      |> Calendar.DateTime.Parse.unix!
      |> Calendar.Strftime.strftime!("%Y/%m/%d/%H/%M_%S_000.jpg")
    "#{seaweedfs}/#{camera_exid}/snapshots/recordings/#{directory_path}"
  end

  def cleanup_all do
    CloudRecording.get_all_ephemeral
    |> Enum.map(fn(cloud_recording) -> cleanup(cloud_recording) end)
  end

  def cleanup(nil), do: :noop
  def cleanup(%CloudRecording{storage_duration: -1}), do: :noop
  def cleanup(%CloudRecording{status: "paused"}), do: :noop
  def cleanup(%CloudRecording{status: "off"}), do: :noop
  def cleanup(%CloudRecording{camera: nil}), do: :noop
  def cleanup(cloud_recording) do
    cloud_recording.camera.exid
    |> list_expired_days_for_camera(cloud_recording)
    |> Enum.each(fn(day_url) -> delete_directory(cloud_recording.camera.exid, day_url) end)
  end

  defp list_expired_days_for_camera(camera_exid, cloud_recording) do
    ["#{@seaweedfs_new}/#{camera_exid}/snapshots/recordings/"]
    |> list_stored_days_for_camera(["year", "month", "day"])
    |> Enum.filter(fn(day_url) -> expired?(camera_exid, cloud_recording, day_url) end)
    |> Enum.sort
  end

  defp list_stored_days_for_camera(urls, []), do: urls
  defp list_stored_days_for_camera(urls, [_current|rest]) do
    Enum.flat_map(urls, fn(url) ->
      request_from_seaweedfs(url, "Entries", "FullPath")
      |> Enum.map(fn(path) -> "#{url}#{path}/" end)
    end)
    |> list_stored_days_for_camera(rest)
  end

  defp delete_directory(camera_exid, url) do
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 30_000_000]
    date = extract_date_from_url(url, camera_exid)
    case HTTPoison.delete("#{url |> String.replace_suffix("/", "")}?recursive=true", [], hackney: hackney) do
      {:ok, %HTTPoison.Response{body: _}} -> Logger.info "[#{camera_exid}] [storage_delete] [#{date}]"
      {:error, %HTTPoison.Error{reason: reason}} -> Logger.info "[#{camera_exid}] [storage_delete_error] [#{date}] [#{reason}]"
    end
  end

  def expired?(camera_exid, cloud_recording, url) do
    seconds_to_day_before_expiry = (cloud_recording.storage_duration) * (24 * 60 * 60) * (-1)
    day_before_expiry =
      Calendar.DateTime.now_utc
      |> Calendar.DateTime.advance!(seconds_to_day_before_expiry)
      |> Calendar.DateTime.to_date
    url_date = parse_url_date(url, camera_exid)
    Calendar.Date.diff(url_date, day_before_expiry) < 0
  end

  def delete_everything_for(camera_exid) do
    camera_exid
    |> get_camera_apps_list
    |> Enum.map(fn(app_name) -> "#{@seaweedfs}/#{camera_exid}/snapshots/#{app_name}/" end)
    |> list_stored_days_for_camera(["year", "month", "day"])
    |> Enum.each(fn(day_url) -> delete_directory(camera_exid, day_url) end)
  end

  def remove_deleted_cameras do
    request_from_seaweedfs("#{@seaweedfs_new}/", "Directories", "Name")
    |> Enum.filter(fn(exid) -> Camera.by_exid(exid) == nil end)
    |> Enum.each(fn(exid) -> delete_everything_for(exid) end)
  end

  def construct_directory_path(camera_exid, timestamp, app_dir, root_dir \\ @root_dir) do
    timestamp
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.Strftime.strftime!("#{root_dir}/#{camera_exid}/snapshots/#{app_dir}/%Y/%m/%d/%H/")
  end

  def construct_file_name(timestamp) do
    timestamp
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.Strftime.strftime!("%M_%S_%f")
    |> format_file_name
  end

  defp construct_snapshot_record(directory_path, file_name, _, _, :v1, _) do
    %{
      created_at: parse_file_timestamp(directory_path, file_name),
      notes: ""
    }
  end
  defp construct_snapshot_record(directory_path, file_name, _, _, :v2, timezone) do
    %{
      created_at: parse_file_timestamp_v2(directory_path, file_name, timezone),
      notes: ""
    }
  end

  defp parse_file_timestamp(directory_path, file_path) do
    [_, _, _, year, month, day, hour] = String.split(directory_path, "/", trim: true)
    [minute, second, _] = String.split(file_path, "_")

    "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}Z"
    |> Calendar.DateTime.Parse.rfc3339_utc
    |> elem(1)
    |> Calendar.DateTime.Format.unix
  end

  defp parse_file_timestamp_v2(directory_path, file_path, timezone) do
    [_, _, _, year, month, day, hour] = String.split(directory_path, "/", trim: true)
    [minute, second, _] = String.split(file_path, "_")

    "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}Z"
    |> Calendar.DateTime.Parse.rfc3339_utc
    |> elem(1)
    |> Util.datetime_to_iso8601(timezone)
  end

  defp parse_hour(year, month, day, time, timezone) do
    month = String.pad_leading("#{month}", 2, "0")
    day = String.pad_leading("#{day}", 2, "0")

    "#{year}-#{month}-#{day}T#{time}Z"
    |> Calendar.DateTime.Parse.rfc3339_utc
    |> elem(1)
    |> Calendar.DateTime.shift_zone!(timezone)
  end

  defp parse_day(year, month, day, timezone) do
    date = Calendar.DateTime.now_utc
    month = String.pad_leading("#{month}", 2, "0")
    day = String.pad_leading("#{day}", 2, "0")
    hour = String.pad_leading("#{date.hour}", 2, "0")
    minute = String.pad_leading("#{date.minute}", 2, "0")
    second = String.pad_leading("#{date.second}", 2, "0")

    "#{year}-#{month}-#{day}T#{hour}:#{minute}:#{second}Z"
    |> Calendar.DateTime.Parse.rfc3339_utc
    |> elem(1)
    |> Calendar.DateTime.shift_zone!(timezone)
  end

  defp parse_url_date(url, camera_exid) do
    url
    |> extract_date_from_url(camera_exid)
    |> String.replace("/", "-")
    |> Calendar.Date.Parse.iso8601!
  end

  defp extract_date_from_url(url, camera_exid) do
    url
    |> String.replace_leading("#{@seaweedfs_new}/#{camera_exid}/snapshots/", "")
    |> String.replace_trailing("/", "")
  end

  defp format_file_name(<<file_name::bytes-size(6)>>) do
    "#{file_name}000" <> ".jpg"
  end

  defp format_file_name(<<file_name::bytes-size(7)>>) do
    "#{file_name}00" <> ".jpg"
  end

  defp format_file_name(<<file_name::bytes-size(9), _rest :: binary>>) do
    "#{file_name}" <> ".jpg"
  end

  defp lookup_dir_paths(camera_exid, apps_list, datetime) do
    timestamp = Calendar.DateTime.Format.unix(datetime)

    Enum.reduce(apps_list, %{}, fn(app_name, map) ->
      dir_path = construct_directory_path(camera_exid, timestamp, app_name, "")
      Map.put(map, app_name, dir_path)
    end)
  end

  defp notes_to_app_name(notes) do
    case notes do
      "Evercam Proxy" -> "recordings"
      "Evercam Thumbnail" -> "thumbnail"
      "Evercam Timelapse" -> "timelapse"
      "Evercam SnapMail" -> "snapmail"
      _ -> "archives"
    end
  end

  defp parse_timestamp(unix_timestamp) do
    case Calendar.DateTime.Parse.rfc3339_utc("#{unix_timestamp}") do
      {:ok, datetime} -> datetime
      {:bad_format, nil} ->
        unix_timestamp
        |> Calendar.DateTime.Parse.unix!
        |> Calendar.DateTime.to_erl
        |> Calendar.DateTime.from_erl!("Etc/UTC")
    end
  end

  defp not_is_between?(snapshot_date, from, to) do
    snapshot_date = parse_timestamp(snapshot_date)
    !is_after_from?(snapshot_date, from) || !is_before_to?(snapshot_date, to)
  end

  defp is_after_from?(snapshot_date, from) do
    case Calendar.DateTime.diff(snapshot_date, from) do
      {:ok, _seconds, _, :after} -> true
      _ -> false
    end
  end

  defp is_before_to?(snapshot_date, to) do
    case Calendar.DateTime.diff(snapshot_date, to) do
      {:ok, _seconds, _, :before} -> true
      _ -> false
    end
  end

  ######################################
  ## Timelapse functions to save/load ##
  ######################################

  def save_timelapse_metadata(camera_id, timelapse_id, low, medium, high) do
    hackney = [pool: :seaweedfs_upload_pool]
    file_path = "/#{camera_id}/timelapses/#{timelapse_id}/metadata.json"
    url = @seaweedfs_new <> file_path

    data =
      case HTTPoison.get(url, [], hackney: hackney) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          body
          |> Poison.decode!
          |> Map.put("low", low)
          |> Map.put("medium", medium)
          |> Map.put("high", high)
          |> Poison.encode!
        {:ok, %HTTPoison.Response{status_code: 404}} ->
          Poison.encode!(%{low: low, medium: medium, high: high})
        error ->
          raise "Metadata upload at '#{file_path}' failed with: #{inspect error}"
      end
    HTTPoison.post!(url, {:multipart, [{file_path, data, []}]}, [], hackney: hackney)
  end

  def load_timelapse_metadata(camera_id, timelapse_id) do
    file_path = "/#{camera_id}/timelapses/#{timelapse_id}/metadata.json"
    url = @seaweedfs_new <> file_path

    hackney = [pool: :seaweedfs_download_pool]
    case HTTPoison.get(url, [], hackney: hackney) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        Poison.decode!(body)
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        %{}
      error ->
        raise "Metadata download from '#{url}' failed with: #{inspect error}"
    end
  end

  def load_hls_menifiest(camera_exid, timelapse_id, file_name) do
    hackney = [pool: :seaweedfs_download_pool]
    url = "#{@seaweedfs_new}/#{camera_exid}/timelapses/#{timelapse_id}/ts/#{file_name}"
    case HTTPoison.get(url, [], hackney: hackney) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} -> body
      {:ok, %HTTPoison.Response{status_code: 404}} -> nil
      error ->
        raise "Menifiest load at '#{url}' failed with: #{inspect error}"
    end
  end

  def save_hls_files(camera_exid, timelapse_id, file_name) do
    "#{@root_dir}/#{camera_exid}/timelapses/#{timelapse_id}/ts/#{file_name}"
    |> File.open([:read, :binary, :raw], fn(file) -> IO.binread(file, :all) end)
    |> case do
      {:ok, content} -> seaweedfs_save_hls_file(camera_exid, timelapse_id, content, file_name)
      {:error, _error} -> {:error, "Failed to read video file."}
    end
  end

  def seaweedfs_save_hls_file(camera_exid, timelapse_id, content, file_name) do
    hackney = [pool: :seaweedfs_upload_pool]
    file_path = "/#{camera_exid}/timelapses/#{timelapse_id}/ts/#{file_name}"
    post_url = "#{@seaweedfs_new}#{file_path}"
    case HTTPoison.post(post_url, {:multipart, [{file_path, content, []}]}, [], hackney: hackney) do
      {:ok, _response} -> :noop
      {:error, error} -> Logger.info "[save_hls] [#{camera_exid}] [#{timelapse_id}] [#{inspect error}]"
    end
  end

  def save_timelapse_manifest(camera_id, timelapse_id, content) do
    hackney = [pool: :seaweedfs_upload_pool]
    file_path = "/#{camera_id}/timelapses/#{timelapse_id}/index.m3u8"
    url = @seaweedfs_new <> file_path

    case HTTPoison.get(url, [], hackney: hackney) do
      {:ok, %HTTPoison.Response{status_code: 200, body: _body}} -> :noop
      _ ->
        HTTPoison.post!(url, {:multipart, [{file_path, content, []}]}, [], hackney: hackney)
    end
  end
end
