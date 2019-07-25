defmodule EvercamMedia.MoveSdCardToCloud do

  @moduledoc """
    `run` method is going to take a **start_date** (Unixtimestamp, integer), **end_date** (Unixtimestamp, integer), **camera_exid** (Unique id, string)

     ## Example

        iex(2)> EvercamMedia.MoveSdCardToCloud.run(1536305214, 1537169214, "pgssr-tswhk")
  """

  import SweetXml
  import EvercamMedia.Snapshot.Storage, only: [seaweedfs_save: 4]
  require Logger

  @contentmgmtsearch "/ISAPI/ContentMgmt/search"
  @max_results 200
  @days_in_sec 200 # This will vary with the frequency of image and image count

  def run(start_date, end_date, camera_exid) do
    {:ok, _} = Application.ensure_all_started(:evercam_media)

    camera = Camera.by_exid(camera_exid)
    %{"auth" => auth, "url" => "http://" <> host_port} = Camera.get_camera_info(camera_exid)
    timezone = Camera.get_timezone(camera)

    spawn fn ->
      start_extraction(start_date, end_date, auth, host_port, camera_exid, timezone)
    end
  end

  defp start_extraction(start_date, end_date, auth, host_port, camera_exid, timezone) do
    xm_s_date =
      start_date
      |> Calendar.DateTime.Parse.unix!
      |> Calendar.Strftime.strftime!("%Y-%m-%dT%H:%M:%SZ")
    xm_e_date =
      start_date + @days_in_sec
      |> not_greater_than_actual_date(end_date)
      |> Calendar.DateTime.Parse.unix!
      |> Calendar.Strftime.strftime!("%Y-%m-%dT%H:%M:%SZ")

    add_date_to_xml(xm_s_date, xm_e_date)
    |> fetch_local_urls(auth, host_port)
    |> extract_jpegs_and_inject(auth, host_port, camera_exid, timezone)

    case start_date + @days_in_sec > end_date do
      true -> :ok
      false -> start_extraction(start_date + @days_in_sec, end_date, auth, host_port, camera_exid, timezone)
    end
  end

  defp not_greater_than_actual_date(start_date, end_date) when start_date > end_date, do: end_date
  defp not_greater_than_actual_date(start_date, _end_date), do: start_date

  defp extract_jpegs_and_inject([], _auth, _host_port, _camera_exid, _timezone), do: :ok
  defp extract_jpegs_and_inject(urls, auth, host_port, camera_exid, timezone) do
    urls
    |> Enum.each(fn(url) ->
      %URI{
        path: path,
        query: query,
      } = List.to_string(url) |> URI.parse
      hearders = ["Authorization": "Basic #{Base.encode64("#{auth}")}"]
      options = [recv_timeout: 15000]
      url = "http://#{host_port}#{path}?#{query}"
      "endtime=" <> start_date = String.split(url, "&") |> Enum.take(2) |> List.last
      {:ok, save_date} = start_date  |> Calendar.DateTime.Parse.rfc3339_utc

      with {:ok, image} <- download_image(hearders, options, url, 4) do
        seaweedfs_save(camera_exid, shift_zone_to_utc(save_date, timezone) |> DateTime.to_unix, image, "Evercam Proxy")
      else
        _ -> Logger.info "No Image after 4 tries."
      end
    end)
  end

  defp download_image(_hearders, _options, _url, 0), do: {:error, ""}
  defp download_image(hearders, options, url, tries) do
    with {:ok, %HTTPoison.Response{body: image, status_code: 200}} <- HTTPoison.get(url, hearders, options) do
      {:ok, image}
    else
      _ -> download_image(hearders, options, url, tries - 1)
    end
  end

  defp shift_zone_to_utc(date, timezone) do
    %{year: year, month: month, day: day, hour: hour, minute: minute, second: second} = date
    Calendar.DateTime.from_erl!({{year, month, day}, {hour, minute, second}}, timezone)
    |> Calendar.DateTime.shift_zone!("UTC")
  end

  defp fetch_local_urls(request_xml, auth, host_port) do
    HTTPoison.post(
      "http://#{host_port}#{@contentmgmtsearch}",
      request_xml,
      [
        "Content-Type": "application/x-www-form-urlencoded",
        "Authorization": "Basic #{Base.encode64("#{auth}")}",
        "SOAPAction": "http://www.w3.org/2003/05/soap-envelope"
      ]
    ) |> handle_response
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: 200, body: body}}) do
    body |> xpath(~x"//searchMatchItem/mediaSegmentDescriptor/playbackURI/text()"l)
  end
  defp handle_response(_), do: []

  defp add_date_to_xml(start_date, end_date) do
    "<?xml version='1.0' encoding='utf-8'?>
      <CMSearchDescription>
        <searchID>C8212F5E-5A10-0001-AE3F-12A0ABB0103A</searchID>
        <trackIDList>
          <trackID>103</trackID>
        </trackIDList>
        <timeSpanList>
          <timeSpan>
            <startTime>#{start_date}</startTime>
            <endTime>#{end_date}</endTime>
          </timeSpan>
        </timeSpanList>
        <contentTypeList>
          <contentType>metadata</contentType>
        </contentTypeList>
        <maxResults>#{@max_results}</maxResults>
        <searchResultPostion>0</searchResultPostion>
        <metadataList>
          <metadataDescriptor>//recordType.meta.std-cgi.com/CMR</metadataDescriptor>
        </metadataList>
      </CMSearchDescription>"
  end
end
