defmodule EvercamMedia.StorageJson do

  use GenServer
  require Logger
  import Ecto.Query

  alias EvercamMedia.Snapshot.Storage
  alias EvercamMedia.Util

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    if Application.get_env(:evercam_media, :start_camera_workers) do
      spawn(fn ->
        check_for_online_json_file()
        |> whats_next(args)
      end)
    end
    {:ok, 1}
  end

  defp whats_next(:ok, "refresh"), do: whats_next(:start, "refresh")
  defp whats_next(:ok, _), do: :noop
  defp whats_next(:start, _args) do
    Logger.info "Starting to create storage.json."
    construction_cameras =
      Camera
      |> preload(:owner)
      |> order_by(desc: :created_at)
      |> Evercam.Repo.all

    years = ["2015", "2016", "2017", "2018", "2019"]

    big_data =
      Enum.map(construction_cameras, fn camera ->
        years_data =
          :ets.match_object(:storage_servers, {:_, :_, :_, :_, :_})
          |> Enum.sort
          |> Enum.reverse
          |> Enum.map(fn(server) ->
            {_, _, _, _, [server_detail]} = server
            url = "#{server_detail.url}/#{camera.exid}/snapshots/recordings/"
            Enum.map(years, fn year ->
              final_url = url <> year <> "/"
              %{
                "#{year}" => Storage.request_from_seaweedfs(final_url, server_detail.type, server_detail.attribute)
              }
            end)
          end) |> Enum.flat_map(& &1) |> Enum.reduce(&Map.merge(&1, &2, fn _, v1, v2 ->
            v1 ++ v2
          end)) |> Enum.map(fn {k, v} -> {k, Enum.uniq(v)} end) |> Map.new
        %{
          camera_name: camera.name,
          camera_exid: camera.exid,
          camera_id: camera.id,
          owner_id: camera.owner.id,
          oldest_snapshot_date: _snapshot_date(:oldest, camera),
          latest_snapshot_date: _snapshot_date(:latest, camera),
          years: years_data
        }
      end)
    seaweedfs_save(big_data, 1)
  end

  defp _snapshot_date(atom, camera) do
    timezone = Camera.get_timezone(camera)
    case atom do
      :latest ->
        case Storage.seaweed_thumbnail_load(camera.exid) do
          {:ok, date, _image} -> Util.convert_unix_to_iso(date, timezone)
          _ -> ""
        end
      :oldest ->
        case Storage.get_or_save_oldest_snapshot(camera.exid) do
          {:ok, _image, date} -> Util.convert_unix_to_iso(date, timezone)
          _ -> ""
        end
    end
  end

  def check_for_online_json_file do
    Logger.info "Checking for online file."
    [{_, _, _, _, [server]}] = :ets.match_object(:storage_servers, {:_, "RW", :_, :_, :_})
    with {:ok, %HTTPoison.Response{status_code: 200}} <- HTTPoison.get(
                              "#{server.url}/evercam-admin3/storage.json",
                              ["Accept": "application/json"],
                              hackney: [pool: :seaweedfs_download_pool]
                            )
    do :ok
    else
      _ ->
        :start
    end
  end

  def seaweedfs_save(_data, _tries = 4), do: :noop
  def seaweedfs_save(data, tries) do
    [{_, _, _, _, [server]}] = :ets.match_object(:storage_servers, {:_, "RW", :_, :_, :_})
    hackney = [pool: :seaweedfs_upload_pool]
    case HTTPoison.post("#{server.url}/evercam-admin3/storage.json", {:multipart, [{"/evercam-admin3/storage.json", Jason.encode!(data), []}]}, [], hackney: hackney) do
      {:ok, response} -> response
      {:error, error} ->
        seaweedfs_save(data, tries + 1)
        Logger.info "[seaweedfs_save_storage_json] [#{inspect error}]"
    end
  end
end
