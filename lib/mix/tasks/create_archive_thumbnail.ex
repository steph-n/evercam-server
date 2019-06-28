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
          try do
            Logger.info "Start create thumbnail for compare: #{compare.exid}, camera: #{compare.camera.exid}"
            download_images_and_create_thumbnail(compare)
          catch _type, error ->
            IO.inspect error
          end
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

  defp download_images_and_create_thumbnail(compare) do
    path = "#{@root_dir}/#{compare.exid}/"
    directory_path = S3.construct_compare_bucket_path(compare.camera.exid, compare.exid)
    start_path = S3.construct_compare_file_name(compare.before_date, "start")
    end_path = S3.construct_compare_file_name(compare.after_date, "end")
    {:ok, start_image} = S3.do_load("#{directory_path}#{start_path}")
    {:ok, end_image} = S3.do_load("#{directory_path}#{end_path}")
    File.mkdir_p(path)
    File.write("#{path}/before_image.jpg", start_image)
    File.write("#{path}/after_image.jpg", end_image)
    evercam_logo = Path.join(Application.app_dir(:evercam_media), "priv/static/images/evercam-logo-white.png")
    export_thumbnail(compare.camera.exid, compare.exid, path, evercam_logo)

    animated_file = "#{path}#{compare.exid}.gif"
    animation_command = "convert -depth 8 -gravity SouthEast -define jpeg:size=1280x720 \\( #{evercam_logo} -resize '100x100!' \\) -write MPR:logo +delete \\( #{path}before_image.jpg -resize '1280x720!' MPR:logo -geometry +15+15 -composite -write MPR:before \\) \\( #{path}after_image.jpg  -resize '1280x720!' MPR:logo -geometry +15+15 -composite -write MPR:after  \\) +append -quantize transparent -colors 250 -unique-colors +repage -write MPR:commonmap +delete MPR:after  -map MPR:commonmap +repage -write MPR:after  +delete MPR:before -map MPR:commonmap +repage -write MPR:before \\( MPR:after -set delay 25 -crop 15x0 -reverse \\) MPR:after \\( MPR:before -set delay 27 -crop 15x0 \\) -set delay 2 -loop 0 -write #{animated_file} +delete 0--2"
    mp4_command = "ffmpeg -f gif -i #{animated_file} -pix_fmt yuv420p -c:v h264_nvenc -movflags +faststart -filter:v crop='floor(in_w/2)*2:floor(in_h/2)*2' #{path}#{compare.exid}.mp4"
    command = "#{animation_command} && #{mp4_command}"
    case Porcelain.shell(command).out do
      "" ->
        upload_path = "#{compare.camera.exid}/compares/#{compare.exid}/"
        S3.do_save_multiple(%{
          "#{animated_file}" => "#{upload_path}#{compare.exid}.gif",
          "#{path}#{compare.exid}.mp4" => "#{upload_path}#{compare.exid}.mp4"
        })
      _ -> :noop
    end
    File.rm_rf(path)
  end

  defp create_thumbnail(id, path) do
    Porcelain.shell("ffmpeg -i #{path}#{id}.mp4 -vframes 1 -vf scale=640:-1 -y #{path}thumb-#{id}.jpg", [err: :out]).out
  end

  defp export_thumbnail(camera_exid, compare_id, root, evercam_logo) do
    arrow = Path.join(Application.app_dir(:evercam_media), "priv/static/images/arrow-symbol.png")
    left_arrow = "\\( #{arrow} -resize '40x70!' \\) -geometry +650+330 -composite "
    right_arrow = "\\( #{arrow} -resize '40x70!' -rotate 180 \\) -geometry +587+330 -composite"
    line = "-stroke red -strokewidth 8 -draw 'line 640,0 640,720'"
    cmd = "convert -size 1280x720 xc:None -background None \\( #{root}before_image.jpg -resize '1280x720!' -crop 640x720+0+0 \\) -gravity West -composite \\( #{root}after_image.jpg -resize '1280x720!' -crop 640x720+640+0 \\) -gravity East -composite \\( #{evercam_logo} -resize '100x100!' \\) -geometry +15+15 -gravity SouthEast -composite #{left_arrow} #{right_arrow} #{line} -resize 640x #{root}thumb-#{compare_id}.jpg"

    case Porcelain.shell(cmd).out do
      "" ->
        upload_path = "#{camera_exid}/compares/#{compare_id}/"
        S3.do_save_multiple(%{
          "#{root}thumb-#{compare_id}.jpg" => "#{upload_path}thumb-#{compare_id}.jpg"
        })
      _ -> :noop
    end
  end
end
