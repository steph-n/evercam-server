defmodule EvercamMediaWeb.CloudRecordingController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  alias EvercamMedia.Snapshot.WorkerSupervisor
  alias EvercamMediaWeb.SnapshotExtractorView
  alias EvercamMedia.Util
  import EvercamMedia.Validation.CloudRecording

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  swagger_path :cloud_extraction do
    post "/cameras/{id}/apps/cloud-recording/extract"
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

  def cloud_extraction(conn, %{"id" => exid} = params) do
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
          extraction_pid = spawn(fn ->
            EvercamMedia.UserMailer.snapshot_extraction_started(full_snapshot_extractor, "Cloud")
            start_snapshot_extractor(config)
          end)
          :ets.insert(:extractions, {exid <> "-cloud-#{full_snapshot_extractor.id}", extraction_pid})
          conn
          |> put_status(:created)
          |> put_view(SnapshotExtractorView)
          |> render("show.json", %{snapshot_extractor: full_snapshot_extractor})
        {:error, changeset} ->
          render_error(conn, 400, Util.parse_changeset(changeset))
      end
    end
  end

  swagger_path :delete_cloud_extraction do
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

  def delete_cloud_extraction(conn, %{"id" => exid, "extraction_id" => extraction_id}) do
    with [{exid, extraction_pid}] <- :ets.lookup(:extractions, exid <> "-cloud-#{extraction_id}"),
         true                     <- Process.exit(extraction_pid, :kill),
         {:ok, _}                 <- File.rm_rf("#{@root_dir}/#{exid}/extract/#{extraction_id}/"),
         {1, nil}                 <- SnapshotExtractor.delete_by_id(extraction_id),
         true                     <- :ets.delete(:extractions, exid <> "-cloud-#{extraction_id}")
   do
     json(conn, %{message: "Cloud Extraction has been deleted for camera: #{exid}"})
   else
    _ ->
      json(conn, %{message: "Cloud Extraction is not running for this camera."})
   end
  end

  swagger_path :show do
    get "/cameras/{id}/apps/cloud-recording"
    summary "Returns the cloud recording of given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Recordings"
    response 200, "Success"
    response 401, "Invalid API keys"
    response 403, "Unauthorized"
  end

  def show(conn, %{"id" => exid}) do
    current_user = conn.assigns[:current_user]
    camera = Camera.by_exid_with_associations(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn),
         :ok <- ensure_can_edit(current_user, camera, conn),
         do: camera.cloud_recordings |> render_cloud_recording(conn)
  end

  swagger_path :create do
    post "/cameras/{id}/apps/cloud-recording"
    summary "Create new cloud recording of given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      frequency :query, :integer, "Frequency, For example 60", required: true
      storage_duration :query, :integer, "Duration, For example 90", required: true
      status :query, :string, "", enum: ["on-scheduled","off","on","paused"], required: true
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
         :ok <- ensure_can_edit(current_user, camera, conn),
         :ok <- validate_params(params) |> ensure_params(conn)
    do
      cr_params = %{
        camera_id: camera.id,
        frequency: params["frequency"],
        storage_duration: params["storage_duration"],
        status: params["status"],
        schedule: get_json(params["schedule"])
      }

      old_cloud_recording = camera.cloud_recordings || %CloudRecording{}
      action_log = get_action_log(camera.cloud_recordings)
      case old_cloud_recording |> CloudRecording.changeset(cr_params) |> Repo.insert_or_update do
        {:ok, cloud_recording} ->
          camera = camera |> Repo.preload(:cloud_recordings, force: true)
          Camera.invalidate_camera(camera)
          exid
          |> String.to_atom
          |> Process.whereis
          |> WorkerSupervisor.update_worker(camera)

          extra = %{
            agent: get_user_agent(conn, params["agent"]),
            cr_settings: %{
              old: set_settings(old_cloud_recording),
              new: set_settings(cloud_recording)
            }
          }
          |> Map.merge(get_requester_Country(user_request_ip(conn, params["requester_ip"]), params["u_country"], params["u_country_code"]))
          Util.log_activity(current_user, camera, "cloud recordings #{action_log}", extra)
          send_email_on_cr_change(Application.get_env(:evercam_media, :run_spawn), current_user, camera, cloud_recording, old_cloud_recording, user_request_ip(conn, params["requester_ip"]))
          render(conn, "cloud_recording.json", %{cloud_recording: cloud_recording})
        {:error, changeset} ->
          render_error(conn, 400, changeset)
      end
    end
  end

   swagger_path :nvr_days do
    get "/cameras/{id}/nvr/recordings/{year}/{month}/days"
    summary "Returns recorded days on nvr in a given month."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      year :path, :string, "Year, for example 2013", required: true
      month :path, :string, "Month, for example 10", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Nvr"
    response 200, "Success"
    response 404, "No recordings found or Camera does not found"
  end

  def nvr_days(conn, %{"id" => exid, "year" => year, "month" => month}) do
    camera = Camera.by_exid_with_associations(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn)
    do
      ip = Camera.host(camera, "external")
      port = Camera.get_nvr_port(camera)
      cam_username = Camera.username(camera)
      cam_password = Camera.password(camera)
      channel = VendorModel.get_channel(camera, camera.vendor_model.channel)

      case EvercamMedia.HikvisionNVR.get_recording_days(ip, port, cam_username, cam_password, channel, year, month) do
        {:ok, body} ->
          days = EvercamMedia.XMLParser.parse_xml(body, '/trackDailyDistribution/dayList/day/dayOfMonth')
          records = EvercamMedia.XMLParser.parse_xml(body, '/trackDailyDistribution/dayList/day/record')
          record_days =
            days
            |> Enum.with_index
            |> Enum.map(fn(item) ->
              {day, index} = item
              case records |> Enum.at(index) do
                "true" -> day
                "false" -> ""
              end
            end)
            |> Enum.uniq
          json(conn, %{days: record_days})
        {:error} -> render_error(conn, 404, "No recordings found")
      end
    end
  end

  swagger_path :nvr_hours do
    get "/cameras/{id}/nvr/recordings/{year}/{month}/{day}/hours"
    summary "Returns recorded hours on nvr in a given day."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      year :path, :string, "Year, for example 2013", required: true
      month :path, :string, "Month, for example 10", required: true
      day :path, :string, "Day, for example 24", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Nvr"
    response 200, "Success"
    response 404, "No recordings found or Camera does not found"
  end

  def nvr_hours(conn, %{"id" => exid, "year" => year, "month" => month, "day" => day}) do
    camera = Camera.by_exid_with_associations(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn)
    do
      ip = Camera.host(camera, "external")
      port = Camera.get_nvr_port(camera)
      cam_username = Camera.username(camera)
      cam_password = Camera.password(camera)
      timezone = Camera.get_timezone(camera)
      channel = VendorModel.get_channel(camera, camera.vendor_model.channel)
      date = "#{year}-#{month}-#{day}"
      starttime = "#{date}T00:00:00Z"
      endtime = "#{date}T23:59:59Z"
      current_datetime = Calendar.DateTime.now_utc |> Calendar.DateTime.shift_zone!(timezone)

      case EvercamMedia.HikvisionNVR.get_stream_urls(camera.exid, ip, port, cam_username, cam_password, channel, starttime, endtime) do
        {:ok, body} ->
          starttime_list = EvercamMedia.XMLParser.parse_xml(body, '/CMSearchResult/matchList/searchMatchItem/timeSpan/startTime')
          endtime_list = EvercamMedia.XMLParser.parse_xml(body, '/CMSearchResult/matchList/searchMatchItem/timeSpan/endTime')
          meta_data = EvercamMedia.XMLParser.parse_single(body, '/CMSearchResult/matchList/searchMatchItem[1]/metadataMatches/metadataDescriptor')
          hours = parse_hours(String.contains?(meta_data, "motion"), starttime_list, endtime_list, date, current_datetime)

          json(conn, %{hours: hours})
        {:error} -> render_error(conn, 404, "No recordings found")
      end
    end
  end

  def hikvision_nvr(conn, %{"id" => exid, "starttime" => starttime, "endtime" => endtime}) do
    %{assigns: %{version: version}} = conn
    camera = Camera.by_exid_with_associations(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn)
    do
      ip = Camera.host(camera, "external")
      port = Camera.port(camera, "external", "rtsp")
      cam_username = Camera.username(camera)
      cam_password = Camera.password(camera)
      channel = VendorModel.get_channel(camera, camera.vendor_model.channel)
      timezone = Camera.get_timezone(camera)
      from_date = convert_timestamp(version, starttime, timezone)
      end_date = convert_timestamp(version, endtime, timezone)

      case EvercamMedia.HikvisionNVR.publish_stream_from_rtsp(camera.exid, ip, port, cam_username, cam_password, channel, from_date, end_date) do
        {:ok} -> json(conn, %{message: "Streaming started."})
        {:stop} -> render_error(conn, 406, "System creating clip")
        {:error} -> render_error(conn, 404, "No recordings found")
      end
    end
  end

  swagger_path :stop do
    get "/cameras/{id}/nvr/recordings/stop"
    summary "Turns off the streaming of the given camera."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Nvr"
    response 200, "Success"
    response 404, "No stream running or Camera does not found"
  end

  def stop(conn, %{"id" => exid}) do
    camera = Camera.by_exid_with_associations(exid)
    with :ok <- ensure_camera_exists(camera, exid, conn)
    do
      ip = Camera.host(camera, "external")
      port = Camera.port(camera, "external", "rtsp")
      cam_username = Camera.username(camera)
      cam_password = Camera.password(camera)
      case EvercamMedia.HikvisionNVR.stop(camera.exid, ip, port, cam_username, cam_password) do
        {:ok} -> json(conn, %{message: "Streaming stopped."})
        {:error} -> render_error(conn, 404, "No stream running")
      end
    end
  end

  swagger_path :get_recording_times do
    get "/cameras/{id}/nvr/videos"
    summary "Returns the recording time chunks in an hour."
    parameters do
      id :path, :string, "Unique identifier for camera.", required: true
      starttime :query, :string, "ISO8601 (2019-02-18T09:00:00.000+00:00)"
      endtime :query, :string, "ISO8601 (2019-02-18T09:00:00.000+00:00)"
      api_id :query, :string, "The Evercam API id for the requester."
      api_key :query, :string, "The Evercam API key for the requester."
    end
    tag "Nvr"
    response 200, "Success"
    response 401, "Invalid API keys"
    response 404, "Camera does not exist"
  end

  def get_recording_times(conn, %{"id" => exid, "starttime" => starttime, "endtime" => endtime}) do
    %{assigns: %{version: version}} = conn
    camera = Camera.by_exid_with_associations(exid)

    with :ok <- ensure_camera_exists(camera, exid, conn)
    do
      ip = Camera.host(camera, "external")
      port = Camera.get_nvr_port(camera)
      cam_username = Camera.username(camera)
      cam_password = Camera.password(camera)
      channel = VendorModel.get_channel(camera, camera.vendor_model.channel)
      timezone = Camera.get_timezone(camera)
      from_date = convert_timestamp_to_rfc(version, starttime, timezone)
      to_date = convert_timestamp_to_rfc(version, endtime, timezone)
      case EvercamMedia.HikvisionNVR.get_stream_urls(camera.exid, ip, port, cam_username, cam_password, channel, from_date, to_date) do
        {:ok, body} ->
          starttime_list = EvercamMedia.XMLParser.parse_xml(body, '/CMSearchResult/matchList/searchMatchItem/timeSpan/startTime')
          endtime_list = EvercamMedia.XMLParser.parse_xml(body, '/CMSearchResult/matchList/searchMatchItem/timeSpan/endTime')
          meta_data = EvercamMedia.XMLParser.parse_single(body, '/CMSearchResult/matchList/searchMatchItem[1]/metadataMatches/metadataDescriptor')

          cond do
            Enum.count(starttime_list) > 0 ->
              times_list =
                String.contains?(meta_data, "motion")
                |> get_times_list(starttime_list, endtime_list)
                |> get_off_times_list(convert_timestamp_to_rfc(version, endtime, timezone))
                |> get_off_times_start(convert_timestamp_to_rfc(version, starttime, timezone))
              json(conn, %{times_list: times_list})
            true ->
              render_error(conn, 404, "No recordings found")
          end

        {:error} -> render_error(conn, 404, "No recordings found")
      end
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

  defp get_times_list(true, starttime_list, endtime_list) do
    starttime_list
    |> Enum.with_index
    |> Enum.map(fn(item) ->
      {timestamp, index} = item
      stime = String.replace(timestamp, "T", " ") |> String.replace("Z", "")
      etime = endtime_list |> Enum.at(index) |> String.replace("T", " ") |> String.replace("Z", "")
      [stime, 1, etime]
    end)
  end
  defp get_times_list(false, starttime_list, endtime_list) do
    starttime_list
    |> Enum.with_index
    |> Enum.reduce([], fn(item, times_list) ->
      {timestamp, index} = item
      starttime = convert_timestap_from_rfc(timestamp)
      endtime = convert_timestap_from_rfc(Enum.at(endtime_list, index))
      {:ok, seconds, _, _} = Calendar.DateTime.diff(endtime, starttime)

      times_list ++ get_timespan_chunk(starttime, endtime, [], seconds)
    end)
  end

  defp get_off_times_start([], _starttime), do: []
  defp get_off_times_start(times_list, starttime) do
    last_recording_time = List.first(List.first(times_list))
    starttime_str = starttime |> String.replace("T", " ") |> String.replace("Z", "")
    cond do
      starttime_str == last_recording_time -> times_list
      true -> [["#{starttime_str}", 0, "#{last_recording_time}"]] ++ times_list
    end
  end

  defp get_off_times_list([], _endtime), do: []
  defp get_off_times_list(times_list, endtime) do
    last_recording_time = List.last(List.last(times_list))
    endtime_str = endtime |> String.replace("T", " ") |> String.replace("Z", "")
    times_list ++ [["#{last_recording_time}", 0, "#{endtime_str}"]]
  end

  defp get_timespan_chunk(starttime, endtime, times_list, seconds) when seconds > 0 do
    cond do
      seconds > 59 ->
        starttime_str = starttime |> Calendar.Strftime.strftime!("%Y-%m-%d %H:%M:%S")
        endtime_str = starttime |> Calendar.DateTime.advance!(59) |> Calendar.Strftime.strftime!("%Y-%m-%d %H:%M:%S")
        times_list = times_list ++ [["#{starttime_str}", 1, "#{endtime_str}"]]
        adv_starttime = Calendar.DateTime.advance!(starttime, 60)
        get_timespan_chunk(adv_starttime, endtime, times_list, seconds - 60)
      true ->
        starttime_str = starttime |> Calendar.Strftime.strftime!("%Y-%m-%d %H:%M:%S")
        endtime_str = endtime |> Calendar.Strftime.strftime!("%Y-%m-%d %H:%M:%S")
        times_list ++ [["#{starttime_str}", 1, "#{endtime_str}"]]
    end
  end
  defp get_timespan_chunk(_starttime, _endtime, times_list, _seconds), do: times_list

  defp parse_hours(true, starttime_list, _endtime_list, date, current_datetime) do
    current_date = current_datetime |> Calendar.Strftime.strftime!("%Y-%m-%d")
    ehour =
      cond do
        date == current_date ->
          current_datetime |> Calendar.Strftime.strftime!("%H") |> String.to_integer
        true ->
          23
      end
    shour = starttime_list |> List.first |> get_hour_from_timestap
    extract_hours([], shour, ehour)
  end
  defp parse_hours(false, starttime_list, endtime_list, _date, _current_date) do
    starttime_list
    |> Enum.with_index
    |> Enum.reduce([], fn(item, hours) ->
      {timestamp, index} = item
      shour = get_hour_from_timestap(timestamp)
      ehour = get_hour_from_timestap(Enum.at(endtime_list, index))
      hours ++ extract_hours([], shour, ehour)
    end)
    |> List.flatten
    |> Enum.uniq
  end

  defp extract_hours(hours, shour, ehour) when shour <= ehour do
    extract_hours(hours ++ [shour], shour + 1, ehour)
  end
  defp extract_hours(hours, _shour, _ehour) do
    hours
  end

  defp convert_timestamp_to_rfc(:v1, timestamp, _) do
    timestamp
    |> String.to_integer
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.Strftime.strftime!("%Y-%m-%dT%H:%M:%SZ")
  end
  defp convert_timestamp_to_rfc(:v2, timestamp, timezone) do
    {:ok, datetime} = Calendar.DateTime.Parse.rfc3339(timestamp, timezone)
    Calendar.Strftime.strftime!(datetime, "%Y-%m-%dT%H:%M:%SZ")
  end

  defp convert_timestamp(:v1, timestamp, _) do
    timestamp
    |> String.to_integer
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.Strftime.strftime!("%Y%m%dT%H%M%SZ")
  end
  defp convert_timestamp(:v2, timestamp, timezone) do
    {:ok, datetime} = Calendar.DateTime.Parse.rfc3339(timestamp, timezone)
    Calendar.Strftime.strftime!(datetime, "%Y%m%dT%H%M%SZ")
  end

  defp convert_timestap_from_rfc(timestamp) do
    case Calendar.DateTime.Parse.rfc3339_utc(timestamp) do
      {:ok, datetime} -> datetime
      {:bad_format, nil} -> nil
    end
  end

  defp get_hour_from_timestap(timestamp) do
    case Calendar.DateTime.Parse.rfc3339_utc(timestamp) do
      {:ok, datetime} ->
        datetime
        |> Calendar.Strftime.strftime!("%H")
        |> String.to_integer
      {:bad_format, nil} -> nil
    end
  end

  defp set_settings(cloud_recording) do
    case cloud_recording.camera_id do
      nil -> nil
      _ ->
        %{status: cloud_recording.status, storage_duration: cloud_recording.storage_duration, frequency: cloud_recording.frequency, schedule: cloud_recording.schedule}
    end
  end

  defp send_email_on_cr_change(false, _current_user, _camera, _cloud_recording, _old_cloud_recording, _user_request_ip), do: :noop
  defp send_email_on_cr_change(true, current_user, camera, cloud_recording, old_cloud_recording, user_request_ip) do
    try do
      Task.start(fn ->
        EvercamMedia.UserMailer.cr_settings_changed(current_user, camera, cloud_recording, old_cloud_recording, user_request_ip)
      end)
    catch _type, error ->
      Logger.error inspect(error)
      Logger.error Exception.format_stacktrace System.stacktrace
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

  defp ensure_params(:ok, _conn), do: :ok
  defp ensure_params({:invalid, message}, conn), do: json(conn, %{error: message})

  defp get_json(schedule) do
    case Poison.decode(schedule) do
      {:ok, json} -> json
    end
  end

  defp render_cloud_recording(nil, conn), do: conn |> render("show.json", %{cloud_recording: []})
  defp render_cloud_recording(cl, conn), do: conn |> render("cloud_recording.json", %{cloud_recording: cl})

  defp get_action_log(nil), do: "created"
  defp get_action_log(_cloud_recording), do: "updated"
end
