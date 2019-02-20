defmodule EvercamMedia.MoveOldWeedData do
  @moduledoc """
  This task will be used to move Old all camera recordings before 01-11-2018 to new storage server
  """
  alias Evercam.Repo
  import Ecto.Query
  require Logger

  @seaweedfs Application.get_env(:evercam_media, :seaweedfs_url_1)
  @seaweedfs_new Application.get_env(:evercam_media, :seaweedfs_url_new)
  @root_dir Application.get_env(:evercam_media, :storage_dir)

  def migrate_snapshots do
    {:ok, _} = Application.ensure_all_started(:evercam_media)
    cameras_exids = get_cameras_to_move()
    move_snapshots(cameras_exids)
  end

  def migrate_thumbnails do
    {:ok, _} = Application.ensure_all_started(:evercam_media)
    cameras_exids = get_cameras_to_move()
    move_thumbnails(cameras_exids)
  end

  defp move_snapshots(exids) do
    exids
    |> Enum.each(fn (exid) ->
      request_from_seaweedfs("#{@seaweedfs}/#{exid}/snapshots/recordings/", "Directories", "Name")
      |> Enum.sort |> Enum.each(fn (year) ->
        request_from_seaweedfs("#{@seaweedfs}/#{exid}/snapshots/recordings/#{year}/", "Directories", "Name")
        |> Enum.sort |> Enum.each(fn (month) ->
          request_from_seaweedfs("#{@seaweedfs}/#{exid}/snapshots/recordings/#{year}/#{month}/", "Directories", "Name")
          |> Enum.sort |> Enum.each(fn (day) ->
            request_from_seaweedfs("#{@seaweedfs}/#{exid}/snapshots/recordings/#{year}/#{month}/#{day}/", "Directories", "Name")
            |> Enum.sort |> Enum.each(fn (hour) ->
              request_from_seaweedfs("#{@seaweedfs}/#{exid}/snapshots/recordings/#{year}/#{month}/#{day}/#{hour}/?limit=3600", "Files", "name")
              |> Enum.sort |> Enum.each(fn (file) ->
                exist_on_seaweed?("/#{exid}/snapshots/recordings/#{year}/#{month}/#{day}/#{hour}/#{file}")
                |> copy_or_skip("/#{exid}/snapshots/recordings/#{year}/#{month}/#{day}/#{hour}/#{file}")
                save_current_directory(exid, year, month, day, hour, file)
              end)
            end)
          end)
        end)
      end)
    end)
  end

  defp save_current_directory(exid, year, month, day, hour, file) do
    File.write!("#{@root_dir}/moving_old_data", "#{exid} #{year} #{month} #{day} #{hour} #{file}")
  end

  defp move_thumbnails(exids) do
    exids
    |> Enum.each(fn (exid) ->
      exist_on_seaweed?("/#{exid}/snapshots/thumbnail.jpg")
      |> copy_or_skip("/#{exid}/snapshots/thumbnail.jpg")
    end)
  end

  defp request_from_seaweedfs(url, type, attribute) do
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 15000]
    with {:ok, response} <- HTTPoison.get(url, ["Accept": "application/json"], hackney: hackney),
         %HTTPoison.Response{status_code: 200, body: body} <- response,
         {:ok, data} <- Poison.decode(body),
         true <- is_list(data[type]) do
      Enum.map(data[type], fn(item) -> item[attribute] end)
    else
      _ -> []
    end
  end

  defp exist_on_seaweed?(url) do
    hackney = [pool: :seaweedfs_download_pool, recv_timeout: 30_000_000]
    case HTTPoison.get("#{@seaweedfs}#{url}", ["Accept": "application/json"], hackney: hackney) do
      {:ok, %HTTPoison.Response{status_code: 200, body: data}} -> {:ok, data}
      _error ->
        :not_found
    end
  end

  defp copy_or_skip(:not_found, _path), do: :noop
  defp copy_or_skip({:ok, data}, path) do
    hackney = [pool: :seaweedfs_upload_pool]
    case HTTPoison.post("#{@seaweedfs_new}#{path}", {:multipart, [{path, data, []}]}, [], hackney: hackney) do
      {:ok, %HTTPoison.Response{status_code: 201, body: body}} ->
        Logger.info "[seaweedfs_save] [#{body}]"
      {:error, error} ->
        Logger.info "[seaweedfs_save] [#{inspect error}]"
    end
  end

  defp get_cameras_to_move do
    CloudRecording
    |> where([cl], cl.storage_duration == -1)
    |> where([cl], cl.status != "off")
    |> preload(:camera)
    |> Repo.all
    |> Enum.filter(& !is_nil(&1.camera))
    |> Enum.map(fn (cr) ->
      from_date = Calendar.DateTime.from_erl!({{2017, 11, 01}, {00, 00, 00}}, "UTC")
      case Calendar.DateTime.diff(from_date, cr.camera.created_at) do
        {:ok, _, _, :before} -> cr.camera.exid
        _ -> nil
      end
    end) |> Enum.reject(&is_nil/1) |> Enum.sort
  end
end
