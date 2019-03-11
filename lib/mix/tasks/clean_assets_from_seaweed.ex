defmodule EvercamMedia.CleanAssetsFromSeaweed do
  @moduledoc """
  This task will be used to clean all assets form seaweed and from S3 for deleted cameras.
  """
  alias EvercamMedia.Snapshot.Storage
  require Logger

  def clean_weed(server_ip, type, attribute) do
    Storage.request_from_seaweedfs("http://#{server_ip}/?limit=3600", type, attribute)
    |> Enum.each(fn(exid) ->
      delete_directory(exid, "http://#{server_ip}/#{exid}/clips/?recursive=true")
    end)
  end

  defp delete_directory(camera_exid, url) do
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 30_000_000]
    Logger.info "[#{camera_exid}] [delete_assets] [#{url}]"
    HTTPoison.delete!(url, [], hackney: hackney)
  end
end
