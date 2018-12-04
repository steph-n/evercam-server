defmodule EvercamMedia.DeleteZeroByteThumbnails do
  require Logger

  @seaweedfs_new Application.get_env(:evercam_media, :seaweedfs_url_new)

  def update_thumbnail do
    "#{@seaweedfs_new}/?limit=10000"
    |> request_from_seaweedfs("Entries", "FullPath")
    |> Enum.each(fn(camera) ->
      "#{@seaweedfs_new}/#{camera}/snapshots/thumbnail.jpg"
      |> HTTPoison.get([], hackney: [pool: :seaweedfs_download_pool])
      |> handle_response
    end)
  end

  defp handle_response({:ok, %HTTPoison.Response{status_code: 404, request_url: request_url}}) do
    HTTPoison.delete("#{request_url}", [], hackney: [pool: :seaweedfs_download_pool, recv_timeout: 30_000_000])
    |> IO.inspect
  end
  defp handle_response(_), do: :noop

  defp request_from_seaweedfs(url, type, attribute) do
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 15000]
    with {:ok, response} <- HTTPoison.get(url, ["Accept": "application/json"], hackney: hackney),
         %HTTPoison.Response{status_code: 200, body: body} <- response,
         {:ok, data} <- Poison.decode(body),
         true <- is_list(data[type]) do
      Enum.map(data[type], fn(item) -> item[attribute] |> Path.basename end)
    else
      _ -> []
    end
  end
end
