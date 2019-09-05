defmodule Commons do
  def get_file_size(image_path) do
    File.stat(image_path) |> stats()
  end

  def stats({:ok, %File.Stat{size: size}}), do: {:ok, size}
  def stats({:error, reason}), do: {:error, reason}

  def write_sessional_values(session_id, file_size, upload_image_path, path) do
    File.write!("#{path}SESSION", "#{session_id} #{file_size} #{upload_image_path}\n", [:append])
  end

  def check_1000_chunk(path) do
    File.read!("#{path}SESSION") |> String.split("\n", trim: true)
  end

  def commit_if_1000(1000, client, path) do
    entries =
      path
      |> check_1000_chunk()
      |> Enum.map(fn entry ->
        [session_id, offset, upload_image_path] = String.split(entry, " ")
        %{"cursor" => %{"session_id" => session_id, "offset" => String.to_integer(offset)}, "commit" => %{"path" => upload_image_path}}
      end)
    ElixirDropbox.Files.UploadSession.finish_batch(client, entries)
    File.rm_rf!("#{path}SESSION")
  end
  def commit_if_1000(_, _client, _path), do: :noop

  def get_count(images_path) do
    case File.exists?(images_path) do
      true ->
        Enum.count(File.ls!(images_path))
      _ ->
        0
    end
  end

  def clean_images(images_directory) do
    File.rm_rf!(images_directory)
  end

  def save_current_jpeg_time(name, path) do
    File.write!("#{path}CURRENT", name)
  end

  def humanize_time(seconds) do
    Float.floor(seconds / 60)
  end

  def ambiguous_handle(value) do
    case value do
      {:ok, datetime} -> datetime
      {:ambiguous, datetime} -> datetime.possible_date_times |> hd
    end
  end

  def get_head_tail([]), do: []
  def get_head_tail(nil), do: []
  def get_head_tail([head|tail]) do
    [[head]|get_head_tail(tail)]
  end

  def find_difference(end_date, start_date) do
    case Calendar.DateTime.diff(end_date, start_date) do
      {:ok, seconds, _, :after} -> seconds
      _ -> 1
    end
  end

  def unix_timestamp(hours, minutes, date, nil) do
    unix_timestamp(hours, minutes, date, "UTC")
  end
  def unix_timestamp(hours, minutes, date, timezone) do
    %{year: year, month: month, day: day} = date
    {h, _} = Integer.parse(hours)
    {m, _} = Integer.parse(minutes)
    erl_date_time = {{year, month, day}, {h, m, 0}}
    case Calendar.DateTime.from_erl(erl_date_time, timezone) do
      {:ok, datetime} -> datetime |> Calendar.DateTime.Format.unix
      {:ambiguous, datetime} -> datetime.possible_date_times |> hd |> Calendar.DateTime.Format.unix
      _ -> raise "Timezone conversion error"
    end
  end

  def round_2(0), do: 2
  def round_2(n), do: n + 1

  def intervaling(0), do: 1
  def intervaling(n), do: n
end
