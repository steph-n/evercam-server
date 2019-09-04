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

  def session_file_exists?(path) do
    File.exists?("#{path}SESSION")
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
end