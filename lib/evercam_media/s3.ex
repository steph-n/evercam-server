defmodule EvercamMedia.S3 do
  @moduledoc """
  TODO
  """
  require Logger
  @region Application.get_env(:ex_aws, :region)

  def create_bucket(bucket_path) do
    Logger.debug "[create_bucket] [#{bucket_path}]"
    ExAws.S3.put_bucket("evercam-camera-assets/#{bucket_path}", @region)
    |> ExAws.request!
  end

  def save_compare(camera_exid, compare_exid, timestamp, image, _notes, state, opts \\ []) do
    directory_path = construct_compare_bucket_path(camera_exid, compare_exid)
    file_path = construct_compare_file_name(timestamp, state)
    opts = Enum.concat(opts, [content_type: "image/jpeg"])
    "#{directory_path}#{file_path}"
    |> do_save(image, opts)
  end

  def save(camera_exid, timestamp, image, _notes, opts \\ []) do
    Logger.debug "[#{camera_exid}] [snapshot_upload] [#{timestamp}]"
    directory_path = construct_bucket_path(camera_exid, timestamp)
    file_path = construct_file_name(timestamp)
    opts = Enum.concat(opts, [content_type: "image/jpeg"])
    "#{directory_path}#{file_path}"
    |> do_save(image, opts)
  end

  def delete_object(files) do
    ExAws.S3.delete_multiple_objects("evercam-camera-assets", files)
    |> ExAws.request!
  end

  def do_save(path, content, opts) do
    ExAws.S3.put_object("evercam-camera-assets", path, content, opts)
    |> ExAws.request!
  end

  def do_save_multiple(paths) do
    upload_file = fn {src_path, dest_path} ->
      ExAws.S3.put_object("evercam-camera-assets", dest_path, File.read!(src_path), [acl: :public_read])
      |> ExAws.request!
    end
    paths
    |> Task.async_stream(upload_file, max_concurrency: 10, timeout: :infinity)
    |> Stream.run
  end

  def make_file_public(camera_exid, timestamp) do
    directory_path = construct_bucket_path(camera_exid, timestamp)
    file_path = construct_file_name(timestamp)
    do_change_acl("#{directory_path}#{file_path}", [acl: :public_read])
    Logger.debug "Made file public read #{directory_path}#{file_path}"
  end

  def do_change_acl(path, acl) do
    ExAws.S3.put_object_acl("evercam-camera-assets", path, acl)
    |> ExAws.request!
  end

  def days(camera_exid, year, month) do
    month = String.pad_leading("#{month}", 2, "0")
    prefix = "#{camera_exid}/snapshots/#{year}/#{month}/"
    response = ExAws.S3.list_objects("evercam-camera-assets", prefix: prefix, delimiter: "/") |> ExAws.request!

    case response.body.common_prefixes do
      [] -> []
      days ->
        days
        |> Enum.map(fn(day) ->
          day.prefix
          |> String.replace(prefix, "")
          |> String.replace("/", "")
          |> String.to_integer
        end)
    end
  end

  def snapshots_info(camera_exid, year, month, day, version \\ :v1) do
    month = String.pad_leading("#{month}", 2, "0")
    day = String.pad_leading("#{day}", 2, "0")
    prefix = "#{camera_exid}/snapshots/#{year}/#{month}/#{day}/"
    response = ExAws.S3.list_objects("evercam-camera-assets", prefix: prefix, delimiter: "/") |> ExAws.request!

    case response.body.contents do
      [] -> []
      snapshots ->
        snapshots
        |> Enum.reject(fn(snapshot) -> snapshot.key == prefix end)
        |> Enum.map(fn(snapshot) ->
          key = snapshot.key
          created_at =
            key
            |> String.replace("#{camera_exid}/snapshots/", "")
            |> String.replace(".jpg", "")
            |> Timex.parse!("%Y/%m/%d/%H_%M_%S", :strftime)
            |> Timex.to_unix
            %{key: key, created_at: get_iso_date(version, created_at)}
        end)
    end
  end

  def load(camera_exid, timestamp) do
    file_path = convert_timestamp_to_path(timestamp)
    "#{camera_exid}/snapshots/#{file_path}"
    |> do_load
  end

  def do_load(path) do
    case ExAws.S3.get_object("evercam-camera-assets", path) |> ExAws.request do
      {:ok, response} -> {:ok, response.body}
      {:error, {:http_error, code, response}} ->
        message = EvercamMedia.XMLParser.parse_single(response.body, '/Error/Message')
        {:error, code, message}
    end
  end

  def load_compare_thumbnail(camera_exid, compare_id) do
    get_url = "#{camera_exid}/compares/#{compare_id}/thumb-#{compare_id}.jpg"
    case ExAws.S3.get_object("evercam-camera-assets", get_url) |> ExAws.request do
      {:ok, response} -> response.body
      {:error, _} -> EvercamMedia.Util.default_thumbnail
    end
  end

  def get_presigned_url_to_object(path) do
    ExAws.Config.new(:s3)
    |> ExAws.S3.presigned_url(:get, "evercam-camera-assets", path)
  end

  defp convert_timestamp_to_path(timestamp) do
    timestamp
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.Strftime.strftime!("%Y/%m/%d/%H_%M_%S.jpg")
  end

  def construct_bucket_path(camera_exid, timestamp) do
    timestamp
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.Strftime.strftime!("#{camera_exid}/snapshots/%Y/%m/%d/")
  end

  def construct_file_name(timestamp) do
    timestamp
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.Strftime.strftime!("%H_%M_%S.jpg")
  end

  def construct_compare_bucket_path(camera_exid, compare_exid) do
    "#{camera_exid}/compares/#{compare_exid}/"
  end

  def construct_compare_file_name(timestamp, state) do
    timestamp
    |> Calendar.Strftime.strftime!("#{state}-%Y-%m-%d-%H_%M_%S.jpg")
  end

  defp get_iso_date(:v1, timestamp), do: timestamp
  defp get_iso_date(:v2, timestamp) do
    timestamp
    |> Calendar.DateTime.Parse.unix!
    |> Calendar.DateTime.Format.iso8601
  end
end
