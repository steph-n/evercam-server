defmodule EvercamMediaWeb.ArchiveView do
  use EvercamMediaWeb, :view
  alias EvercamMedia.Util

  def render("index.json", %{archives: archives, compares: compares}) do
    archives_list = render_many(archives, __MODULE__, "archive.json")
    compares_list =
      Enum.map(compares, fn(compare) -> render_compare_archive(compare) end)
    %{archives: archives_list ++ compares_list}
  end

  def render("show.json", %{archive: nil}), do: %{archives: []}
  def render("show.json", %{archive: archive}) do
    %{archives: render_many([archive], __MODULE__, "archive.json")}
  end

  def render("archive.json", %{archive: archive}) do
    %{
      id: archive.exid,
      camera_id: archive.camera.exid,
      title: archive.title,
      from_date: Util.ecto_datetime_to_unix(archive.from_date),
      to_date: Util.ecto_datetime_to_unix(archive.to_date),
      created_at: Util.ecto_datetime_to_unix(archive.created_at),
      status: status(archive.status),
      requested_by: Util.deep_get(archive, [:user, :username], ""),
      requester_name: User.get_fullname(archive.user),
      requester_email: Util.deep_get(archive, [:user, :email], ""),
      embed_time: archive.embed_time,
      frames: archive.frames,
      public: archive.public,
      embed_code: "",
      file_name: archive.file_name,
      type: get_type(archive.url, archive.file_name),
      media_url: archive.url,
      thumbnail_url: "#{EvercamMediaWeb.Endpoint.static_url}/v1/cameras/#{archive.camera.exid}/archives/#{archive.exid}/thumbnail?type=clip"
    }
  end

  def render_compare_archive(compare) do
    %{
      id: compare.exid,
      camera_id: compare.camera.exid,
      title: compare.name,
      from_date: Util.ecto_datetime_to_unix(compare.before_date),
      to_date: Util.ecto_datetime_to_unix(compare.after_date),
      created_at: Util.ecto_datetime_to_unix(compare.inserted_at),
      status: compare_status(compare.status),
      requested_by: Util.deep_get(compare, [:user, :username], ""),
      requester_name: User.get_fullname(compare.user),
      requester_email: Util.deep_get(compare, [:user, :email], ""),
      embed_time: false,
      frames: 2,
      public: true,
      file_name: "",
      media_url: "",
      embed_code: compare.embed_code,
      type: "Compare",
      thumbnail_url: "#{EvercamMediaWeb.Endpoint.static_url}/v1/cameras/#{compare.camera.exid}/archives/#{compare.exid}/thumbnail?type=compare"
    }
  end

  defp get_type(media_url, file_name) when media_url in [nil, ""] do
    cond do
      file_name != nil && file_name != "" ->
        "File"
      true ->
        "Clip"
    end
  end
  defp get_type(_media_url, _file_name), do: "URL"

  defp status(0), do: "Pending"
  defp status(1), do: "Processing"
  defp status(2), do: "Completed"
  defp status(3), do: "Failed"

  defp compare_status(0), do: "Processing"
  defp compare_status(1), do: "Completed"
  defp compare_status(2), do: "Failed"
end
