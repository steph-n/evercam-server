defmodule EvercamMedia.CreateArchiveThumbnail do
  alias Evercam.Repo
  alias EvercamMedia.Snapshot.Storage
  alias EvercamMedia.TimelapseRecording.S3
  import Ecto.Query
  require Logger

  @root_dir Application.get_env(:evercam_media, :storage_dir)

  def run_archive do
    {:ok, _} = Application.ensure_all_started(:evercam_media)

    Archive
    |> preload(:camera)
    |> Repo.all
    |> Enum.each(fn(archive) ->
      case archive.camera do
        nil -> Logger.info "Camera not found with id: #{archive.camera_id}, Archive: #{archive.exid}"
        _ ->
          seaweed_url = Storage.point_to_seaweed(archive.created_at)
          archive_url = "#{seaweed_url}/#{archive.camera.exid}/clips/#{archive.exid}.mp4"
          Logger.info archive_url
          download_archive_and_create_thumbnail(archive, archive_url)
      end
    end)
  end

  def run_compare do
    {:ok, _} = Application.ensure_all_started(:evercam_media)

    Compare
    |> preload(:camera)
    |> Repo.all
    |> Enum.each(fn(compare) ->
      case compare.camera do
        nil -> Logger.info "Camera not found with id: #{compare.camera_id}, Archive: #{compare.exid}"
        _ ->
          Logger.info "Start create thumbnail for compare: #{compare.exid}, camera: #{compare.camera.exid}"
          download_compare_and_create_thumbnail(compare)
      end
    end)
  end

  defp download_archive_and_create_thumbnail(archive, archive_url) do
    case HTTPoison.get(archive_url, [], hackney: [pool: :seaweedfs_download_pool]) do
      {:ok, %HTTPoison.Response{status_code: 200, body: video}} ->
        path = "#{@root_dir}/#{archive.exid}/"
        File.mkdir_p(path)
        File.write("#{path}/#{archive.exid}.mp4", video)
        create_thumbnail(archive.exid, path)
        Storage.save_archive_thumbnail(archive.camera.exid, archive.exid, path)
        Logger.info "Thumbnail for archive (#{archive.exid}) created and saved to seaweed."
        File.rm_rf path
      {:ok, %HTTPoison.Response{status_code: 404}} -> Logger.info "Archive (#{archive.exid}) not found."
      {:error, _} -> Logger.info "Failed to download archive (#{archive.exid})."
    end
  end

  defp download_compare_and_create_thumbnail(compare) do
    case S3.do_load("#{compare.camera.exid}/compares/#{compare.exid}.mp4") do
      {:ok, response} ->
        path = "#{@root_dir}/#{compare.exid}/"
        File.mkdir_p(path)
        File.write("#{path}/#{compare.exid}.mp4", response)
        create_thumbnail(compare.exid, path)
        S3.do_save("#{compare.camera.exid}/compares/thumb-#{compare.exid}.jpg", File.read!("#{path}thumb-#{compare.exid}.jpg"), [content_type: "image/jpg", acl: :public_read])
        Logger.info "Thumbnail for compare (#{compare.exid}) created and saved to S3."
        File.rm_rf path
      {:error, _, _} -> Logger.info "Failed to download compare (#{compare.exid})."
    end
  end

  defp create_thumbnail(id, path) do
    Porcelain.shell("ffmpeg -i #{path}#{id}.mp4 -vframes 1 -vf scale=640:-1 -y #{path}thumb-#{id}.jpg", [err: :out]).out
  end
end
