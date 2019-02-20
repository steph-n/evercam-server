defmodule EvercamMedia.ArchiveCreator.ArchiveCreator do
  @moduledoc """
  Provides functions to create archive
  """

  use GenStage
  require Logger
  alias Evercam.Repo
  alias EvercamMedia.Snapshot.Storage

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  ######################
  ## Server Callbacks ##
  ######################

  @doc """
  Initialize the snapmail server
  """
  def init(args) do
    {:producer, args}
  end

  @doc """
  """
  def handle_cast({:create_archive, archive_exid}, state) do
    _create_archive(state, archive_exid)
    {:noreply, [], state}
  end

  #####################
  # Private functions #
  #####################
  defp _create_archive(state, archive_exid) do
    archive = Archive.by_exid(archive_exid)
    get_snapshots_and_create_archive(state, archive, archive.status)
  end

  defp get_snapshots_and_create_archive(_state, archive, 0) do
    spawn fn ->
      try do
        Archive.update_status(archive, Archive.archive_status.processing)
        camera = archive.camera
        from = convert_to_unix(archive.from_date)
        to = convert_to_unix(archive.to_date)
        snapshots = Storage.seaweedfs_load_range(camera.exid, from, to)
        total_snapshots = Enum.count(snapshots)
        cond do
          total_snapshots == 0 ->
            failed_creation(archive, "There are no images for the given time period.")
          true ->
            images_directory = "#{@root_dir}/#{archive.exid}/"
            File.mkdir_p(images_directory)
            loop_list(snapshots, camera.exid, images_directory, 0)
            create_mp4(archive.exid, images_directory)
            create_thumbnail(archive.exid, images_directory)
            Storage.save_mp4(camera.exid, archive.exid, images_directory)
            Storage.save_archive_thumbnail(camera.exid, archive.exid, images_directory)
            File.rm_rf images_directory
            update_archive(archive, total_snapshots, Archive.archive_status.completed)
            EvercamMedia.UserMailer.archive_completed(archive, archive.user.email)
        end
      rescue
        error ->
          Logger.error inspect(error)
          Logger.error Exception.format_stacktrace System.stacktrace
          failed_creation(archive, error.message)
      end
    end
  end
  defp get_snapshots_and_create_archive(_state, _archive, _status), do: :noop

  def loop_list([snap | rest], camera_exid, path, index) do
    next_index = download_snapshot(snap, camera_exid, path, index)
    loop_list(rest, camera_exid, path, next_index)
  end
  def loop_list([], _camera_exid, _path, _index), do: :noop

  def download_snapshot(snap, camera_exid, path, index) do
    case Storage.load(camera_exid, snap.created_at, snap.notes) do
      {:ok, image, _notes} ->
        File.write("#{path}#{index}.jpg", image)
        index + 1
      {:error, _error} -> index
    end
  end

  defp create_mp4(id, path) do
    Porcelain.shell("ffmpeg -r 6 -i #{path}%d.jpg -c:v h264_nvenc -r 6 -preset slow -bufsize 1000k -pix_fmt yuv420p -y #{path}#{id}.mp4", [err: :out]).out
  end

  defp create_thumbnail(id, path) do
    Porcelain.shell("ffmpeg -i #{path}#{id}.mp4 -vframes 1 -vf scale=640:-1 -y #{path}thumb-#{id}.jpg", [err: :out]).out
  end

  defp update_archive(archive, frames, status) do
    params = %{frames: frames, status: status}
    changeset = Archive.changeset(archive, params)
    Repo.update(changeset)
  end

  def failed_creation(archive, error_message) do
    {:ok, updated_archive} = Archive.update_status(archive, Archive.archive_status.failed, %{error_message: error_message})
    EvercamMedia.UserMailer.archive_failed(updated_archive, updated_archive.user.email)
  end

  defp convert_to_unix(timestamp) do
    timestamp
    |> Calendar.DateTime.Format.unix
  end
end
