defmodule EvercamMedia.CleanAssetsFromSeaweed do
  @moduledoc """
  This task will be used to clean all assets form seaweed and from S3 for deleted cameras.
  """
  alias EvercamMedia.Snapshot.Storage
  require Logger

  def clean_weed_assets(server_ip, type, attribute, delete) do
    Storage.request_from_seaweedfs("http://#{server_ip}/?limit=3600", type, attribute)
    |> Enum.each(fn(exid) ->
      delete_directory(delete, exid, "http://#{server_ip}/#{exid}/clips/?recursive=true")
    end)
  end

  def clean_recordings_for_deleted_cameras(server_ip, type, attribute, delete) do
    Storage.request_from_seaweedfs("http://#{server_ip}/?limit=4000", type, attribute)
    |> Enum.each(fn(exid) ->
      case Camera.by_exid(exid) do
        nil ->
          Logger.error "Camera (#{exid}) not found"
          delete_directory(delete, exid, "http://#{server_ip}/#{exid}/?recursive=true")
        _ -> Logger.info "Ignore camera (#{exid})."
      end
    end)
  end

  defp delete_directory(true, camera_exid, url) do
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 30_000_000]
    Logger.info "[#{camera_exid}] [delete_assets] [#{url}]"
    HTTPoison.delete!(url, [], hackney: hackney)
  end
  defp delete_directory(_, _, _), do: :noop
end
