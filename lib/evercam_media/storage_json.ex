defmodule EvercamMedia.StorageJson do

  use GenServer
  require Logger
  import Ecto.Query

  alias EvercamMedia.Snapshot.Storage
  alias EvercamMedia.Util

  @seaweedfs_new  Application.get_env(:evercam_media, :seaweedfs_url_new)
  @seaweedfs_old Application.get_env(:evercam_media, :seaweedfs_url)
  @seaweedfs_oldest Application.get_env(:evercam_media, :seaweedfs_url_1)

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    spawn(fn ->
      check_for_online_json_file()
      |> whats_next(args)
    end)
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
    servers = [@seaweedfs_new, @seaweedfs_old, @seaweedfs_oldest]

    big_data =
      Enum.map(construction_cameras, fn camera ->
        years_data =
          Enum.map(servers, fn server ->
            type = seaweefs_type(server)
            attribute = seaweedfs_attribute(server)
            url = server <> "/#{camera.exid}/snapshots/recordings/"
            Enum.map(years, fn year ->
              final_url = url <> year <> "/"
              %{
                "#{year}" => request_from_seaweedfs(final_url, type, attribute)
              }
            end)
          end) |> Enum.flat_map(& &1) |> Enum.reduce(&Map.merge(&1, &2, fn _, v1, v2 ->
            v1 ++ v2
          end)) |> Enum.map(fn {k, v} -> {k, Enum.uniq(v)} end) |> Map.new
        %{
          camera_name: camera.name,
          camera_exid: camera.exid,
          camera_id: camera.id,
          oldest_snapshot_date: _snapshot_date(:oldest, camera),
          latest_snapshot_date: _snapshot_date(:latest, camera),
          years: years_data
        }
      end)
    seaweedfs_save(big_data, 1)
  end

  defp seaweefs_type(@seaweedfs_new), do: "Entries"
  defp seaweefs_type(_), do: "Directories"

  defp seaweedfs_attribute(@seaweedfs_new), do: "FullPath"
  defp seaweedfs_attribute(_), do: "Name"

  defp _snapshot_date(atom, camera) do
    timezone = Camera.get_timezone(camera)
    case atom do
      :latest ->
        {:ok, date, _image} = Storage.seaweed_thumbnail_load(camera.exid)
        Util.convert_unix_to_iso(date, timezone)
      :oldest ->
        {:ok, _image, date} = Storage.get_or_save_oldest_snapshot(camera.exid)
        Util.convert_unix_to_iso(date, timezone)
    end
  end

  def check_for_online_json_file do
    Logger.info "Checking for online file."
    with {:ok, %HTTPoison.Response{status_code: 200}} <- HTTPoison.get(
                              "#{@seaweedfs_new}/evercam-admin3/storage.json",
                              ["Accept": "application/json"],
                              hackney: [pool: :seaweedfs_download_pool]
                            )
    do :ok
    else
      _ ->
        :start
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

  def seaweedfs_save(_data, _tries = 4), do: :noop
  def seaweedfs_save(data, tries) do
    hackney = [pool: :seaweedfs_upload_pool]
    case HTTPoison.post("#{@seaweedfs_new}/evercam-admin3/storage.json", {:multipart, [{"/evercam-admin3/storage.json", Jason.encode!(data), []}]}, [], hackney: hackney) do
      {:ok, response} -> response
      {:error, error} ->
        seaweedfs_save(data, tries + 1)
        Logger.info "[seaweedfs_save] [#{inspect error}]"
    end
  end
end
