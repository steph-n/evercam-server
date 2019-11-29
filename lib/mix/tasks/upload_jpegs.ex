defmodule UploadJpegs do
  @location "/root/evercamtest"
  import EvercamMedia.Snapshot.Storage, only: [seaweedfs_save_sync: 4]

  def start do
    FileExt.ls_r(@location)
    |> Enum.each(fn(file) ->
      Exexif.exif_from_jpeg_file!(file)[:modify_date]
      |> String.replace("\"", "")
      |> parse_datetime
      |> case do
        "" -> :noop
        timestamp ->
          image = File.read!(file)
          seaweedfs_save_sync("everc-lqyvo", timestamp, image, "")
          File.rename(file, "/root/_evercamtest/#{timestamp}.JPG")
      end
    end)
  end

  defp parse_datetime(datetime) do
    Timex.parse(datetime, "{YYYY}:{0M}:{D} {h24}:{m}:{s}")
    |> case do
      {:error, _text} -> ""
      {:ok, value} -> value |> shift_zone_to_utc("UTC") |> DateTime.to_unix
    end
  end

  defp shift_zone_to_utc(date, timezone) do
    %{year: year, month: month, day: day, hour: hour, minute: minute, second: second, microsecond: microsecond} = date
    Calendar.DateTime.from_erl!({{year, month, day}, {hour, minute, second}}, timezone, microsecond)
    |> Calendar.DateTime.shift_zone!("UTC")
  end
end

defmodule FileExt do
  def ls_r(path \\ ".") do
    cond do
      File.regular?(path) -> [path]
      File.dir?(path) ->
        File.ls!(path)
        |> Enum.map(&Path.join(path, &1))
        |> Enum.map(&ls_r/1)
        |> Enum.concat
      true -> []
    end
  end
end
