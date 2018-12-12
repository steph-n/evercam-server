defmodule EvercamMedia.HikvisionNVR do
  require Logger
  alias EvercamMedia.Snapshot.Storage
  alias EvercamMedia.XMLParser
  alias EvercamMedia.HTTPClient

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  @doc """
  Publish camera RTSP stream to RTMP server from NVR
  """
  def publish_stream_from_rtsp(exid, host, port, username, password, channel, starttime, endtime) do
    archive_pids = ffmpeg_pids("#{@root_dir}/#{host}#{port}/archive/")
    with true <- is_creating_clip(archive_pids) do
      {:stop}
    else
      false ->
        rtsp_url = "rtsp://#{username}:#{password}@#{host}:#{port}/Streaming/tracks/"
        kill_published_streams(exid, rtsp_url)
        "ffmpeg -rtsp_transport tcp -i '#{rtsp_url}#{channel}/?starttime=#{starttime}&endtime=#{endtime}' -f lavfi -i aevalsrc=0 -vcodec copy -acodec aac -map 0:0 -map 1:0 -shortest -strict experimental -f flv rtmp://localhost:1935/live/#{exid}"
        |> Porcelain.spawn_shell
        {:ok}
    end
  end

  @doc """
  Give all recorded stream URLs of camera from NVR
  """
  def get_stream_urls(_exid, host, port, username, password, channel, starttime, endtime) do
    xml = "<?xml version='1.0' encoding='utf-8'?><CMSearchDescription><searchID>C5954E12-60B0-0001-954E-999096EF7420</searchID><trackList>"
    xml = "#{xml}<trackID>#{channel}</trackID></trackList><timeSpanList><timeSpan><startTime>#{starttime}</startTime><endTime>#{endtime}</endTime>"
    xml = "#{xml}</timeSpan></timeSpanList><maxResults>600</maxResults><searchResultPostion>0</searchResultPostion><metadataList>"
    xml = "#{xml}<metadataDescriptor>//metadata.psia.org/VideoMotion</metadataDescriptor></metadataList></CMSearchDescription>"

    url = "http://#{host}:#{port}/PSIA/ContentMgmt/search"
    case HTTPoison.post(url, xml, ["Content-Type": "application/x-www-form-urlencoded", "Authorization": "Basic #{Base.encode64("#{username}:#{password}")}", "SOAPAction": "http://www.w3.org/2003/05/soap-envelope"]) do
      {:ok, %HTTPoison.Response{body: body}} -> {:ok, body}
      _ ->
        Logger.error "[get_stream_urls] [#{url}] [#{xml}]"
        {:error}
    end
  end

  @doc """
  Give all days which have recordings on NVR
  """
  def get_recording_days(host, port, username, password, channel, year, month) do
    xml = "<?xml version='1.0' encoding='utf-8'?><trackDailyParam><year>#{year}</year><monthOfYear>#{month}</monthOfYear></trackDailyParam>"

    post_url = "http://#{host}:#{port}/ISAPI/ContentMgmt/record/tracks/#{channel}/dailyDistribution"
    case HTTPoison.post(post_url, xml, ["Content-Type": "application/x-www-form-urlencoded", "Authorization": "Basic #{Base.encode64("#{username}:#{password}")}"]) do
      {:ok, %HTTPoison.Response{body: body}} -> {:ok, body}
      _ ->
        Logger.error "[get_recording_days] [#{post_url}] [#{xml}]"
        {:error}
    end
  end

  @doc """
  Stop running ffmpeg of published RTSP stream
  """
  def stop(exid, host, port, username, password) do
    rtsp_url = "rtsp://#{username}:#{password}@#{host}:#{port}/Streaming/tracks/"
    archive_pids = ffmpeg_pids("#{@root_dir}/#{host}#{port}/archive/")
    kill_published_streams(exid, rtsp_url, archive_pids)
    {:ok}
  end

  @doc """
  Extract clip from NVR recordings
  """
  def extract_clip_from_stream(camera, archive, starttime, endtime) do
    ip = Camera.host(camera, "external")
    port = Camera.port(camera, "external", "rtsp")
    username = Camera.username(camera)
    password = Camera.password(camera)
    channel = VendorModel.get_channel(camera, camera.vendor_model.channel)
    Archive.update_status(archive, Archive.archive_status.processing)
    archive_directory = "#{@root_dir}/#{ip}#{port}/archive/"
    File.mkdir_p(archive_directory)
    rtsp_url = "rtsp://#{username}:#{password}@#{ip}:#{port}/Streaming/tracks/"
    kill_published_streams(camera.exid, rtsp_url)
    Porcelain.shell("ffmpeg -rtsp_transport tcp -i '#{rtsp_url}#{channel}?starttime=#{starttime}&endtime=#{endtime}' -f mp4 -c:v h264_nvenc -pix_fmt yuv420p -b:v 1000 -an #{archive_directory}#{archive.exid}.mp4", [err: :out]).out

    case File.exists?("#{archive_directory}#{archive.exid}.mp4") do
      true ->
        create_thumbnail(archive.exid, archive_directory)
        Storage.save_mp4(camera.exid, archive.exid, archive_directory)
        Storage.save_archive_thumbnail(camera.exid, archive.exid, archive_directory)
        File.rm_rf archive_directory
        Archive.update_status(archive, Archive.archive_status.completed)
        EvercamMedia.UserMailer.archive_completed(archive, archive.user.email)
      _ ->
        Archive.update_status(archive, Archive.archive_status.failed)
        EvercamMedia.UserMailer.archive_failed(archive, archive.user.email)
    end
  end

  defp create_thumbnail(id, path) do
    Porcelain.shell("ffmpeg -i #{path}#{id}.mp4 -vframes 1 -vf scale=640:-1 -y #{path}thumb-#{id}.jpg", [err: :out]).out
  end

  @doc """
  Give complete stream info of specific channel
  """
  def get_stream_info(host, port, username, password, channel) do
    url = "http://#{host}:#{port}/ISAPI/Streaming/channels/#{channel}"
    case HTTPClient.get(:digest_auth, url, username, password) do
      {:ok, %HTTPoison.Response{body: body}} ->
        xml = XMLParser.parse_inner_array(body)
        %{
          video_encoding: XMLParser.parse_single_element(xml, '/StreamingChannel/Video/videoCodecType'),
          resolution: get_value(xml, "resolution"),
          frame_rate: get_value(xml, "framerate"),
          bitrate_type: get_value(xml, "bitrate_type"),
          bitrate: get_value(xml, "bitrate"),
          video_quality: get_value(xml, "videoquality"),
          smart_code: XMLParser.parse_single_element(xml, '/StreamingChannel/Video/SmartCodec/enabled')
        }
      _ -> %{}
    end
  end

  @doc """
  Give NVR device info
  """
  def get_device_info(host, port, username, password) do
    url = "http://#{host}:#{port}/ISAPI/System/deviceInfo"
    case HTTPClient.get(:digest_auth, url, username, password) do
      {:ok, %HTTPoison.Response{body: body}} ->
        xml = XMLParser.parse_inner_array(body)
        %{
          device_name: XMLParser.parse_single_element(xml, '/DeviceInfo/deviceName'),
          device_id: XMLParser.parse_single_element(xml, '/DeviceInfo/deviceID'),
          model: XMLParser.parse_single_element(xml, '/DeviceInfo/model'),
          serial_number: XMLParser.parse_single_element(xml, '/DeviceInfo/serialNumber'),
          mac_address: XMLParser.parse_single_element(xml, '/DeviceInfo/macAddress'),
          firmware_version: XMLParser.parse_single_element(xml, '/DeviceInfo/firmwareVersion'),
          firmware_released_date: XMLParser.parse_single_element(xml, '/DeviceInfo/firmwareReleasedDate'),
          encoder_version: XMLParser.parse_single_element(xml, '/DeviceInfo/encoderVersion'),
          encoder_released_date: XMLParser.parse_single_element(xml, '/DeviceInfo/encoderReleasedDate'),
          device_type: XMLParser.parse_single_element(xml, '/DeviceInfo/deviceType')
        }
      _ -> %{}
    end
  end

  @doc """
  Give HDD info attached with NVR
  """
  def get_hdd_info(host, port, username, password) do
    url = "http://#{host}:#{port}/ISAPI/ContentMgmt/Storage"
    case HTTPClient.get(:digest_auth, url, username, password) do
      {:ok, %HTTPoison.Response{body: body}} ->
        XMLParser.parse_inner_array(body)
        |> XMLParser.parse_inner('/storage/hddList/hdd')
        |> Enum.map(fn(hdd_xml) ->
          %{
            id: XMLParser.parse_element(hdd_xml, '/hdd/id'),
            name: XMLParser.parse_element(hdd_xml, '/hdd/hddName'),
            path: XMLParser.parse_element(hdd_xml, '/hdd/hddPath'),
            type: XMLParser.parse_element(hdd_xml, '/hdd/hddType'),
            status: XMLParser.parse_element(hdd_xml, '/hdd/status'),
            capacity: get_space(XMLParser.parse_element(hdd_xml, '/hdd/capacity')),
            free_space: get_space(XMLParser.parse_element(hdd_xml, '/hdd/freeSpace')),
            property: XMLParser.parse_element(hdd_xml, '/hdd/property')
          }
        end)
      _ -> %{}
    end
  end

  @doc """
  Give VH info from NVR
  """
  def get_vh_info(host, port, username, password, channel) do
    channel_id = parse_chl_id(channel)
    url = "http://#{host}:#{port}/ISAPI/ContentMgmt/InputProxy/channels/#{channel_id}/status"
    case HTTPClient.get(:digest_auth, url, username, password) do
      {:ok, %HTTPoison.Response{body: body}} ->
        xml = XMLParser.parse_inner_array(body)
        vh_port = get_vh_port(XMLParser.parse_single_element(xml, '/InputProxyChannelStatus/url'))
        %{
          ip_address: XMLParser.parse_single_element(xml, '/InputProxyChannelStatus/sourceInputPortDescriptor/ipAddress'),
          manage_port: XMLParser.parse_single_element(xml, '/InputProxyChannelStatus/sourceInputPortDescriptor/managePortNo'),
          online: XMLParser.parse_single_element(xml, '/InputProxyChannelStatus/online'),
          chan_detect_result: XMLParser.parse_single_element(xml, '/InputProxyChannelStatus/chanDetectResult'),
          vh_port: vh_port,
          vh_url: get_vh_url(host, vh_port)
        }
      _ -> %{}
    end
  end

  @doc """
  Download recorded file from NVR in mp4 format
  """
  def download_stream(host, port, username, password, url) do
    xml = "<?xml version='1.0'?><downloadRequest version='1.0' xmlns='http://urn:selfextension:psiaext-ver10-xsd'>"
    xml = "#{xml}<playbackURI>rtsp://#{host}:#{port}#{url}"
    xml = "#{xml}</playbackURI></downloadRequest>"

    path = "#{@root_dir}/stream/stream.mp4"
    File.rm(path)
    url = "http://#{host}:#{port}/PSIA/Custom/SelfExt/ContentMgmt/download"
    opts = [stream_to: self()]
    HTTPoison.post(url, xml, ["Content-Type": "application/x-www-form-urlencoded", "Authorization": "Basic #{Base.encode64("#{username}:#{password}")}", "SOAPAction": "http://www.w3.org/2003/05/soap-envelope"], opts)
    |> collect_response(self(), <<>>)
  end

  def collect_response(id, par, data) do
    receive do
      %HTTPoison.AsyncStatus{code: 200, id: id} ->
        Logger.debug "Collect response status"
        collect_response(id, par, data)
      %HTTPoison.AsyncHeaders{headers: _headers, id: id} ->
        Logger.debug "Collect response headers"
        collect_response(id, par, data)
      %HTTPoison.AsyncChunk{chunk: chunk, id: id,} ->
        save_temporary(chunk)
        collect_response(id, par, data) # <> chunk
      %HTTPoison.AsyncEnd{id: _id} ->
        Logger.debug "Stream complete"
      _ ->
        Logger.debug "Unknown message in response"
        collect_response(id, par, data)
    after
      5000 ->
        Logger.debug "No response after 5 seconds."
    end
  end

  defp save_temporary(chunk) do
    "#{@root_dir}/stream/stream.mp4"
    |> File.open([:append, :binary, :raw], fn(file) -> IO.binwrite(file, chunk) end)
    |> case do
      {:error, :enoent} ->
        File.mkdir_p!("#{@root_dir}/stream/")
        save_temporary(chunk)
      _ -> :noop
    end
  end

  defp kill_published_streams(camera_id, rtsp_url, archive_pids \\ []) do
    rtsp_url
    |> ffmpeg_pids
    |> Enum.reject(fn(pid) -> Enum.member?(archive_pids, pid) end)
    |> Enum.each(fn(pid) -> Porcelain.shell("kill -9 #{pid}") end)
    File.rm_rf!("/tmp/hls/#{camera_id}/")
  end

  defp ffmpeg_pids(rtsp_url) do
    Porcelain.shell("ps -ef | grep ffmpeg | grep '#{rtsp_url}' | grep -v grep | awk '{print $2}'").out
    |> String.split
  end

  defp is_creating_clip([]), do: false
  defp is_creating_clip(_pids), do: true

  defp get_value(xml, "resolution") do
    width = XMLParser.parse_single_element(xml, '/StreamingChannel/Video/videoResolutionWidth')
    height = XMLParser.parse_single_element(xml, '/StreamingChannel/Video/videoResolutionHeight')
    "#{width}x#{height}"
  end
  defp get_value(xml, "bitrate_type") do
    case XMLParser.parse_single_element(xml, '/StreamingChannel/Video/videoQualityControlType') do
      "VBR" -> "Variable"
      "CBR" -> "Constant"
      _ -> ""
    end
  end
  defp get_value(xml, "videoquality") do
    case XMLParser.parse_single_element(xml, '/StreamingChannel/Video/fixedQuality') do
      "20" -> "Lowest"
      "30" -> "Lower"
      "45" -> "Low"
      "60" -> "Medium"
      "75" -> "Higher"
      "90" -> "Highest"
      _ -> ""
    end
  end
  defp get_value(xml, "framerate") do
    case XMLParser.parse_single_element(xml, '/StreamingChannel/Video/maxFrameRate') do
      "" -> ""
      "0" -> "Full Frame Rate"
      "50" -> "1/2"
      "25" -> "1/4"
      "12" -> "1/8"
      "6" -> "1/16"
      frames when frames > 50 ->
        Integer.floor_div(String.to_integer(frames), 100)
    end
  end
  defp get_value(xml, "bitrate") do
    case XMLParser.parse_single_element(xml, '/StreamingChannel/Video/videoQualityControlType') do
      "VBR" -> XMLParser.parse_single_element(xml, '/StreamingChannel/Video/vbrUpperCap')
      "CBR" -> XMLParser.parse_single_element(xml, '/StreamingChannel/Video/constantBitRate')
      _ -> ""
    end
  end

  def get_space(size) do
    "#{Float.floor(String.to_integer(size) / 1024)}Gb"
  end

  def get_vh_port(url) do
    url
    |> String.replace_leading("http://", "")
    |> String.split(":")
    |> List.last
  end

  def parse_chl_id(channel) do
    channel - 1
    |> Integer.floor_div(100)
  end

  def get_vh_url(_ip, vh_port) when vh_port in [nil, ""], do: ""
  def get_vh_url(ip, vh_port) do
    "http://#{ip}:#{vh_port}"
  end
end
