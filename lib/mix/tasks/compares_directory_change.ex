defmodule EvercamMedia.ComparesDirectoryChange do
  require Logger
  alias Evercam.Repo
  alias EvercamMedia.Util

  @bucket "evercam-camera-assets"

  def run do
    Compare.by_status(1)
    |> Enum.each(fn(compare) ->

      start_snapshots_path = path_for_snapshot(compare.before_date)
      end_snapshots_path = path_for_snapshot(compare.after_date)

      start_datetime = new_path_for_snapshot(compare.before_date)
      end_datetime = new_path_for_snapshot(compare.after_date)

      # move files from root compare to compae_exid directory
      src_object = [
        "#{compare.camera.exid}/compares/#{compare.exid}.mp4",
        "#{compare.camera.exid}/compares/#{compare.exid}.gif",
        "#{compare.camera.exid}/compares/thumb-#{compare.exid}.jpg",
        "#{compare.camera.exid}/snapshots/#{start_snapshots_path}.jpg",
        "#{compare.camera.exid}/snapshots/#{end_snapshots_path}.jpg"
      ]

      dest_object = [
        "#{compare.camera.exid}/compares/#{compare.exid}/#{compare.exid}.mp4",
        "#{compare.camera.exid}/compares/#{compare.exid}/#{compare.exid}.gif",
        "#{compare.camera.exid}/compares/#{compare.exid}/thumb-#{compare.exid}.jpg",
        "#{compare.camera.exid}/compares/#{compare.exid}/start-#{start_datetime}.jpg",
        "#{compare.camera.exid}/compares/#{compare.exid}/end-#{end_datetime}.jpg"
      ]

      Enum.each(0..4, fn(x) ->
        Logger.info "Moving Compares for #{compare.camera.exid}"
        move_a_compare(Enum.at(src_object, x), Enum.at(dest_object, x))
      end)

      Logger.info "Updating Compares Embed Code for #{compare.camera.exid}."
      compare
      |> Compare.changeset(%{embed_code: "<div id='evercam-compare'></div><script src='https://dash.evercam.io/assets/evercam_compare.js' class='#{compare.camera.exid} #{start_datetime} #{end_datetime} #{compare.exid} autoplay'></script>"})
      |> Repo.update
      |> embed_code_updated?
    end)
  end

  defp embed_code_updated?({:ok, compare}), do: Logger.info "Embed Code has been updated for #{compare.camera.exid}."
  defp embed_code_updated?({:error, changeset}), do: Logger.info Util.parse_changeset(changeset)

  defp path_for_snapshot(date) do
    date
    |> Calendar.Strftime.strftime!("%Y/%m/%d/%H_%M_%S")
  end

  defp new_path_for_snapshot(date) do
    date
    |> Calendar.Strftime.strftime!("%Y-%m-%d-%H_%M_%S")
  end

  defp move_a_compare(src_object, dest_object) do
    ExAws.S3.put_object_copy(@bucket, dest_object, @bucket, src_object, [acl: :public_read])
    |> ExAws.request
    |> need_another_try(src_object, dest_object)
  end

  defp need_another_try({:ok, %{status_code: 200}}, _src_object, _dest_object), do: :noop
  defp need_another_try(_, src_object, dest_object) do
    move_a_compare(src_object, dest_object)
  end
end
