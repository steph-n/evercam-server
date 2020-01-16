defmodule EvercamMedia.Snapshot.Storage do
  require Logger
  alias EvercamMedia.Util
  import EvercamMedia.S3, only: [do_save: 3, do_load: 1, delete_object: 1]

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  def point_to_seaweed(request_date) do
    :ets.select(:storage_servers,
      [{
        {:_, :_, :"$1", :"$2", :"$3"},
        [{:andalso, {:>, {:const, request_date}, :"$1"}, {:<, {:const, request_date}, :"$2"}}],
        [:"$3"]
      }])
    |> found_server
  end

  defp found_server([]) do
    [{_, _, _, _, [server]}] = :ets.match_object(:storage_servers, {:_, "RW", :_, :_, :_})
    server
  end
  defp found_server([[server]]), do: server

  ####################################
  ###### Save and Get snapshots ######
  ####################################

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
    seaweed_server = point_to_seaweed(timestamp)
    app_name = notes_to_app_name(notes)
    directory_path = construct_directory_path(camera_exid, timestamp, app_name, "")
    file_name = construct_file_name(timestamp)
    url = seaweed_server.url <> directory_path <> file_name

    case HTTPoison.get(url, [], hackney: [pool: :seaweedfs_download_pool]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: snapshot}} ->
        {:ok, snapshot, notes}
      _error ->
        {:error, :not_found}
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

  # Temporary solution for extractor to sync
  def seaweedfs_save_sync(camera_exid, timestamp, image, _notes) do
    seaweed_server = point_to_seaweed(timestamp)
    hackney = [pool: :seaweedfs_upload_pool]
    directory_path = construct_directory_path(camera_exid, timestamp, "recordings", "")
    file_name = construct_file_name(timestamp)
    file_path = directory_path <> file_name
    case HTTPoison.post("#{seaweed_server.url}#{file_path}", {:multipart, [{file_path, image, []}]}, [], hackney: hackney) do
      {:ok, response} -> response
      {:error, error} -> Logger.info "[seaweedfs_save_sync] [#{camera_exid}] [#{inspect error}]"
    end
  end

  def seaweedfs_save(camera_exid, timestamp, image, _notes) do
    [{_, _, _, _, [server]}] = :ets.match_object(:storage_servers, {:_, "RW", :_, :_, :_})
    hackney = [pool: :seaweedfs_upload_pool]
    directory_path = construct_directory_path(camera_exid, timestamp, "recordings", "")
    file_name = construct_file_name(timestamp)
    file_path = directory_path <> file_name
    case HTTPoison.post("#{server.url}#{file_path}", {:multipart, [{file_path, image, []}]}, [], hackney: hackney) do
      {:ok, response} -> response
      {:error, error} -> Logger.info "[seaweedfs_save] [#{file_path}] [#{camera_exid}] [#{inspect error}]"
    end
  end

  def exists_for_day?(camera_exid, from, to, timezone) do
    hours = hours(camera_exid, from, to, timezone)
    !Enum.empty?(hours)
  end

  def nearest(camera_exid, timestamp, version \\ :v1, timezone \\ "UTC") do
    seaweedfs = point_to_seaweed(timestamp)
    list_of_snapshots =
      seaweedfs.app_list
      |> Enum.flat_map(fn(app) -> do_seaweedfs_load_range(camera_exid, timestamp, app, seaweedfs) end)
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

  def days(camera_exid, from, to, timezone) do
    seaweedfs = from |> Calendar.DateTime.Format.unix |> point_to_seaweed
    url_base = "#{seaweedfs.url}/#{camera_exid}/snapshots"
    from_date = Calendar.Strftime.strftime!(from, "%Y/%m")
    to_date = Calendar.Strftime.strftime!(to, "%Y/%m")

    from_days =
      seaweedfs.app_list
      |> Enum.flat_map(fn(app) -> request_from_seaweedfs("#{url_base}/#{app}/#{from_date}/", seaweedfs.type, seaweedfs.attribute) end)
      |> Enum.uniq
      |> Enum.map(fn(day) -> parse_day(from.year, from.month, day, timezone) end)
      |> Enum.reject(fn(datetime) -> Calendar.DateTime.before?(datetime, from) end)

    seaweedfs = to |> Calendar.DateTime.Format.unix |> point_to_seaweed
    url_base = "#{seaweedfs.url}/#{camera_exid}/snapshots"
    to_days =
      seaweedfs.app_list
      |> Enum.flat_map(fn(app) -> request_from_seaweedfs("#{url_base}/#{app}/#{to_date}/", seaweedfs.type, seaweedfs.attribute) end)
      |> irish_life(to_date, camera_exid)
      |> Enum.uniq
      |> Enum.map(fn(day) -> parse_day(to.year, to.month, day, timezone) end)
      |> Enum.reject(fn(datetime) -> Calendar.DateTime.after?(datetime, to) end)

    Enum.concat(from_days, to_days)
    |> Enum.map(fn(datetime) -> datetime.day end)
    |> Enum.sort
    |> Enum.uniq
  end

  defp irish_life(data, date, camera_exid) do
    with true <- irish_life_cameras?(camera_exid),
         true <- october_seventeenth?(date) do
      []
    else
      _ -> data
    end
  end

  defp october_seventeenth?("2017/10"), do: true
  defp october_seventeenth?("2017/10/13"), do: true
  defp october_seventeenth?("2017/10/14"), do: true
  defp october_seventeenth?(_date), do: false

  defp irish_life_cameras?("irish-life-plaza"), do: true
  defp irish_life_cameras?("irish-life-mall"), do: true
  defp irish_life_cameras?(_camera_exid), do: false

  def hours(camera_exid, from, to, timezone) do
    seaweedfs = from |> Calendar.DateTime.Format.unix |> point_to_seaweed
    url_base = "#{seaweedfs.url}/#{camera_exid}/snapshots"
    from_date = Calendar.Strftime.strftime!(from, "%Y/%m/%d")
    to_date = Calendar.Strftime.strftime!(to, "%Y/%m/%d")

    from_hours =
      seaweedfs.app_list
      |> Enum.flat_map(fn(app) -> request_from_seaweedfs("#{url_base}/#{app}/#{from_date}/", seaweedfs.type, seaweedfs.attribute) end)
      |> irish_life(from_date, camera_exid)
      |> Enum.uniq
      |> Enum.map(fn(hour) -> parse_hour(from.year, from.month, from.day, "#{hour}:00:00", timezone) end)
      |> Enum.reject(fn(datetime) -> Calendar.DateTime.before?(datetime, from) end)

    seaweedfs = to |> Calendar.DateTime.Format.unix |> point_to_seaweed
    url_base = "#{seaweedfs.url}/#{camera_exid}/snapshots"
    to_hours =
      seaweedfs.app_list
      |> Enum.flat_map(fn(app) -> request_from_seaweedfs("#{url_base}/#{app}/#{to_date}/", seaweedfs.type, seaweedfs.attribute) end)
      |> irish_life(to_date, camera_exid)
      |> Enum.uniq
      |> Enum.map(fn(hour) -> parse_hour(to.year, to.month, to.day, "#{hour}:00:00", timezone) end)
      |> Enum.reject(fn(datetime) -> Calendar.DateTime.after?(datetime, to) end)

    Enum.concat(from_hours, to_hours)
    |> Enum.map(fn(datetime) -> datetime.hour end)
    |> Enum.sort
    |> Enum.uniq
  end

  def hour(camera_exid, hour_timestamp, version \\ :v1, timezone \\ "UTC") do
    seaweedfs = hour_timestamp |> Calendar.DateTime.Format.unix |> point_to_seaweed
    url_base = "#{seaweedfs.url}/#{camera_exid}/snapshots"
    apps_list = seaweedfs.app_list
    hour_datetime = Calendar.Strftime.strftime!(hour_timestamp, "%Y/%m/%d/%H")
    dir_paths = lookup_dir_paths(camera_exid, apps_list, hour_timestamp)

    apps_list
    |> Enum.map(fn(app_name) ->
      {app_name, request_from_seaweedfs("#{url_base}/#{app_name}/#{hour_datetime}/?limit=3600", seaweedfs.files, seaweedfs.name)}
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
    seaweedfs = point_to_seaweed(from)
    from_date = parse_timestamp(from)
    to_date = parse_timestamp(to)

    seaweedfs.app_list
    |> Enum.flat_map(fn(app) -> do_seaweedfs_load_range(camera_exid, from, app, seaweedfs, version, timezone) end)
    |> Enum.reject(fn(snapshot) -> not_is_between?(snapshot.created_at, from_date, to_date) end)
    |> Enum.sort_by(fn(snapshot) -> snapshot.created_at end)
  end

  defp do_seaweedfs_load_range(camera_exid, from, app_name, seaweedfs, version \\ :v1, timezone \\ "UTC") do
    directory_path = construct_directory_path(camera_exid, from, app_name, "")
    request_from_seaweedfs("#{seaweedfs.url}#{directory_path}?limit=3600", seaweedfs.files, seaweedfs.name)
    |> Enum.reject(fn(file_name) -> file_name == "metadata.json" end)
    |> Enum.reject(fn(file_name) -> String.ends_with?(file_name, ".json") end)
    |> Enum.map(fn(file_name) ->
      construct_snapshot_record(directory_path, file_name, app_name, 0, version, timezone)
    end)
  end

  def request_from_seaweedfs(url, type, attribute) do
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 15000]
    with {:ok, response} <- HTTPoison.get(url, ["Accept": "application/json"], hackney: hackney),
         %HTTPoison.Response{status_code: 200, body: body} <- response,
         {:ok, data} <- Jason.decode(body),
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
    case ConCache.get(:camera_thumbnail, camera_exid) do
      nil ->
        check_camera_last_image(camera_exid)
        case ConCache.get(:camera_thumbnail, camera_exid) do
          nil -> {:error, Util.unavailable}
          {_last_save_date, timestamp, img} -> {:ok, timestamp, img}
        end
      {_last_save_date, timestamp, img} -> {:ok, timestamp, img}
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

  ########################################
  ###### End Save and Get snapshots ######
  ########################################

  ########################################
  ###### Load latest image to cache ######
  ########################################
  def check_camera_last_image(camera_id) do
    :ets.match_object(:storage_servers, {:_, :_, :_, :_, :_})
    |> Enum.sort
    |> Enum.reverse
    |> Enum.map(fn(server) ->
      {_, _, _, _, [server_detail]} = server
      server_detail
    end)
    |> browse_server(camera_id)
  end

  defp browse_server([], _), do: :noop
  defp browse_server([server | rest], camera_id) do
    with {:error, _} <- load_latest_snapshot_to_cache(server, "#{camera_id}/snapshots/recordings"),
         {:error, _} <- load_latest_snapshot_to_cache(server, "#{camera_id}/snapshots/archives")
    do
      browse_server(rest, camera_id)
    else
      {:ok, image, timestamp} -> update_cache_thumbnail("#{camera_id}", timestamp, image)
    end
  end

  defp load_latest_snapshot_to_cache(server, path) do
    hackney = [pool: :seaweedfs_download_pool]
    weed_url = server.url

    with {:year, year} <- get_latest_directory_name(:year, "#{weed_url}/#{path}/", server.type, server.attribute),
         {:month, month} <- get_latest_directory_name(:month, "#{weed_url}/#{path}/#{year}/", server.type, server.attribute),
         {:day, day} <- get_latest_directory_name(:day, "#{weed_url}/#{path}/#{year}/#{month}/", server.type, server.attribute),
         {:hour, hour} <- get_latest_directory_name(:hour, "#{weed_url}/#{path}/#{year}/#{month}/#{day}/", server.type, server.attribute),
         {:image, last_image} <- get_latest_directory_name(:image, "#{weed_url}/#{path}/#{year}/#{month}/#{day}/#{hour}/?limit=3600", server.files, server.name) do
      case HTTPoison.get("#{weed_url}/#{path}/#{year}/#{month}/#{day}/#{hour}/#{last_image}", [], hackney: hackney) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          [minute, second, _] = String.split(last_image, "_")
          datetime =
            {{to_integer(year), to_integer(month), to_integer(day)}, {to_integer(hour), to_integer(minute), to_integer(second)}}
            |> Calendar.DateTime.from_erl("UTC")
            |> elem(1)
            |> Calendar.DateTime.Format.unix
          {:ok, body, datetime}
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
    |> Enum.reject(fn(file_name) -> file_name == "metadata.json" end)
    |> Enum.reject(fn(file_name) -> String.ends_with?(file_name, ".json") end)
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
  def get_or_save_oldest_snapshot(camera_exid, update_image \\ false) do
    [{_, _, _, _, [server]}] = :ets.match_object(:storage_servers, {:_, "RW", :_, :_, :_})
    spawn(fn -> search_oldest_snapshot(update_image, camera_exid) end)
    "#{server.url}/#{camera_exid}/snapshots/"
    |> request_from_seaweedfs(server.type, server.attribute)
    |> Enum.map(fn dir ->
      is_oldest?(dir)
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort(&(&2 > &1))
    |> List.first
    |> load_oldest_snapshot(camera_exid, server)
  end

  defp search_oldest_snapshot(true, camera_exid) do
    :ets.match_object(:storage_servers, {:_, :_, :_, :_, :_})
    |> Enum.sort
    |> Enum.map(fn(server) ->
      {_, _, _, _, [server_detail]} = server
      server_detail
    end)
    |> loop_server_to_find_snap(camera_exid)
  end
  defp search_oldest_snapshot(_, _), do: :noop

  defp loop_server_to_find_snap([], _), do: :noop
  defp loop_server_to_find_snap([server | rest], camera_id) do
    Logger.info "start searching on server: #{server.url}"
    case import_oldest_image(camera_id, server) do
      {:error, _} -> loop_server_to_find_snap(rest, camera_id)
      {:ok, image, datetime} -> Logger.info "Oldest snapshot updated. Server"
    end
  end

  defp is_oldest?(<<"oldest-", _::binary>> = dir), do: dir
  defp is_oldest?(_), do: nil

  def load_oldest_snapshot(<<"oldest-", _::binary>> = file_name, camera_exid, server) do
    url = "#{server.url}/#{camera_exid}/snapshots/"
    case HTTPoison.get("#{url}#{file_name}", [], hackney: [pool: :seaweedfs_download_pool]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: snapshot}} ->
        {:ok, snapshot, take_prefix(file_name, "oldest-")}
      _error ->
        import_oldest_image(camera_exid, server)
    end
  end
  def load_oldest_snapshot(_file_name, camera_exid, server) do
    import_oldest_image(camera_exid, server)
  end

  def take_prefix(full, prefix) do
    base = String.length(prefix)
    String.slice(full, base..-5)
  end

  def import_oldest_image(camera_exid, server) do
    url = "#{server.url}/#{camera_exid}/snapshots/"
    {{year, month, day}, {h, _m, _s}} = Calendar.DateTime.now_utc |> Calendar.DateTime.to_erl

    {snapshot, _error, _datetime} =
      url
      |> request_from_seaweedfs(server.type, server.attribute)
      |> Enum.reduce({{}, {}, {year, month, day, h}}, fn(note, {snapshot, error, datetime}) ->
        {yr, mh, dy, hr} = datetime
        case get_oldest_snapshot(url, note, yr, mh, dy, hr, server) do
          {:ok, image, datetime, y, m, d, h} ->
            {{:ok, image, datetime}, error, {y, m, d, h}}
          {:error, message, y, m, d, h} ->
            {snapshot, {:error, message}, {y, m, d, h}}
        end
      end)
    case snapshot do
      {} -> {:error, Util.unavailable}
      {:ok, image, datetime} ->
        spawn fn -> save_oldest_snapshot(camera_exid, image, datetime, server.url) end
        {:ok, image, datetime}
    end
  end

  def save_oldest_snapshot(camera_exid, image, datetime, weed_url) do
    hackney = [pool: :seaweedfs_upload_pool]
    url = "#{weed_url}/#{camera_exid}/snapshots/oldest-#{datetime}.jpg"
    file_path = "/#{camera_exid}/snapshots/oldest-#{datetime}.jpg"
    case HTTPoison.post(url, {:multipart, [{file_path, image, []}]}, [], hackney: hackney) do
      {:ok, response} -> response
      {:error, error} -> Logger.info "[save_oldest_snapshot] [#{camera_exid}] [#{inspect error}]"
    end
  end

  defp get_oldest_snapshot(url, note, syear, smonth, sday, shour, server) do
    hackney = [pool: :seaweedfs_download_pool]
    date2 = {{syear, smonth, sday}, {shour, 0, 0}}
    with {:year, year} <- get_oldest_directory_name(:year, "#{url}#{note}/", server.type, server.attribute),
         true <- is_previous_date({{to_integer(year), 1, 1}, {0, 0, 0}}, date2, year),
         {:month, month} <- get_oldest_directory_name(:month, "#{url}#{note}/#{year}/", server.type, server.attribute),
         true <- is_previous_date({{to_integer(year), to_integer(month), 1}, {0, 0, 0}}, date2, month),
         {:day, day} <- get_oldest_directory_name(:day, "#{url}#{note}/#{year}/#{month}/", server.type, server.attribute),
         true <- is_previous_date({{to_integer(year), to_integer(month), to_integer(day)}, {0, 0, 0}}, date2, day),
         {:hour, hour} <- get_oldest_directory_name(:hour, "#{url}#{note}/#{year}/#{month}/#{day}/", server.type, server.attribute),
         true <- is_previous_date({{to_integer(year), to_integer(month), to_integer(day)}, {to_integer(hour), 0, 0}}, date2, hour),
         {:image, oldest_image} <- get_oldest_directory_name(:image, "#{url}#{note}/#{year}/#{month}/#{day}/#{hour}/?limit=2", server.files, server.name) do
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

  defp get_oldest_directory_name(directory, url, type, attribute) do
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

  ##########################
  #### End oldest Image ####
  ##########################

  #################################
  ###### Archive Storage fun ######
  #################################

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

  def save_map_file(image_name, url, extension, fileType) do
    case HTTPoison.get("#{url}", [], hackney: [pool: :seaweedfs_download_pool]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: content}} ->
        file_path = "mapping/#{image_name}.#{extension}"
        File.mkdir_p("#{@root_dir}/mapping/")
        File.write("#{@root_dir}/mapping/#{image_name}.#{extension}", content)
        do_save(file_path, content, [content_type: "#{fileType}", acl: :public_read])
        File.rm_rf("#{@root_dir}/mapping/")
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
    delete_object(["#{archive_path}", "#{archive_thumbail_path}"])
    Logger.info "[archive_delete] [#{camera_exid}] [#{archive_id}]"
  end

  #################################
  #### End Archive Storage fun ####
  #################################

  #################################
  #### Delete Storage function ####
  #################################

  def delete_jpegs_with_timestamps(timestamps, camera_exid) do
    Enum.each(timestamps, fn(timestamp) ->
      seaweedfs = point_to_seaweed(timestamp)
      url = create_jpeg_url(seaweedfs.url, timestamp, camera_exid)
      spawn fn ->
        hackney = [pool: :seaweedfs_download_pool, recv_timeout: 30_000]
        HTTPoison.delete!("#{url}?recursive=true", [], hackney: hackney)
      end
    end)
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
  def cleanup(%CloudRecording{camera: %{status: "project_finished"}}), do: :noop
  def cleanup(cloud_recording) do
    cloud_recording.camera.exid
    |> list_expired_days_for_camera(cloud_recording)
    |> Enum.each(fn(day_url) -> delete_directory(cloud_recording.camera.exid, day_url) end)
  end

  defp list_expired_days_for_camera(camera_exid, cloud_recording) do
    [{_, _, _, _, [server]}] = :ets.match_object(:storage_servers, {:_, "RW", :_, :_, :_})
    ["#{server.url}/#{camera_exid}/snapshots/recordings/"]
    |> list_stored_days_for_camera(["year", "month", "day"], server.type, server.attribute)
    |> Enum.filter(fn(day_url) -> expired?(camera_exid, cloud_recording, day_url, server.url) end)
    |> Enum.sort
  end

  defp list_stored_days_for_camera(urls, [], _, _), do: urls
  defp list_stored_days_for_camera(urls, [_current|rest], type, attribute) do
    Enum.flat_map(urls, fn(url) ->
      request_from_seaweedfs(url, type, attribute)
      |> Enum.map(fn(path) -> "#{url}#{path}/" end)
    end)
    |> list_stored_days_for_camera(rest, type, attribute)
  end

  defp delete_directory(camera_exid, url) do
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 30_000_000]
    Enum.each(0..23, fn(hour) ->
      hour_url = url <> String.pad_leading("#{hour}", 2, "0")
      spawn(fn ->
        case HTTPoison.delete("#{hour_url |> String.replace_suffix("/", "")}?recursive=true", [], hackney: hackney) do
          {:ok, %HTTPoison.Response{body: _}} -> Logger.info "[#{camera_exid}] [storage_delete] [#{hour_url}]"
          {:error, %HTTPoison.Error{reason: reason}} -> Logger.info "[#{camera_exid}] [storage_delete_error] [#{hour_url}] [#{reason}]"
        end
      end)
    end)
    HTTPoison.delete("#{url |> String.replace_suffix("/", "")}?recursive=true", [], hackney: hackney)
    Logger.info "[#{camera_exid}] [storage_delete] [#{url}]"
  end

  def expired?(camera_exid, cloud_recording, url, weed_url) do
    seconds_to_day_before_expiry = (cloud_recording.storage_duration) * (24 * 60 * 60) * (-1)
    day_before_expiry =
      Calendar.DateTime.now_utc
      |> Calendar.DateTime.advance!(seconds_to_day_before_expiry)
      |> Calendar.DateTime.to_date
    url_date = parse_url_date(url, camera_exid, weed_url)
    Calendar.Date.diff(url_date, day_before_expiry) < 0
  end

  def delete_everything_for(camera_exid) do
    :ets.match_object(:storage_servers, {:_, :_, :_, :_, :_})
    |> Enum.map(fn(server) ->
      {_, _, _, _, [server_detail]} = server
      server_detail
    end)
    |> do_delete_everything_for(camera_exid)
  end

  defp do_delete_everything_for(camera_exid, server) do
    ["recordings", "archives"]
    |> Enum.map(fn(app_name) -> "#{server.url}/#{camera_exid}/snapshots/#{app_name}/" end)
    |> list_stored_days_for_camera(["year", "month", "day"], server.type, server.attribute)
    |> Enum.each(fn(day_url) -> delete_directory(camera_exid, day_url) end)
  end

  #####################################
  #### End Delete Storage function ####
  #####################################

  ##############################
  ###### Private function ######
  ##############################

  defp create_jpeg_url(seaweedfs, timestamp, camera_exid) do
    directory_path =
      timestamp
      |> Calendar.DateTime.Parse.unix!
      |> Calendar.Strftime.strftime!("%Y/%m/%d/%H/%M_%S_000.jpg")
    "#{seaweedfs}/#{camera_exid}/snapshots/recordings/#{directory_path}"
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

  defp parse_url_date(url, camera_exid, weed_url) do
    url
    |> String.replace_leading("#{weed_url}/#{camera_exid}/snapshots/", "")
    |> String.replace_trailing("/", "")
    |> String.replace("/", "-")
    |> Calendar.Date.Parse.iso8601!
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

  defp to_integer(nil), do: ""
  defp to_integer(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> :error
    end
  end

  ##############################
  #### End Private function ####
  ##############################
end
