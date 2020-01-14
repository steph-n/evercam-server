defmodule EvercamMediaWeb.CompareView do
  use EvercamMediaWeb, :view
  alias EvercamMedia.Util

  def render("index.json", %{compares: compares, version: version}) do
    %{compares: render_many(compares, __MODULE__, "compare.#{version}.json")}
  end

  def render("show.json", %{compare: nil, version: _}), do: %{compares: []}
  def render("show.json", %{compare: compare, version: version}) do
    %{compares: render_many([compare], __MODULE__, "compare.#{version}.json")}
  end

  def render("compare." <> <<version::binary-size(2)>> <> ".json", %{compare: compare}) do
    %{
      id: compare.exid,
      camera_id: compare.camera.exid,
      title: compare.name,
      from_date: date_wrt_version(version, compare.before_date, compare.camera),
      to_date: date_wrt_version(version, compare.after_date, compare.camera),
      created_at: date_wrt_version(version, compare.inserted_at, compare.camera),
      status: status(compare.status),
      requested_by: Util.deep_get(compare, [:user, :username], ""),
      requester_name: User.get_fullname(compare.user),
      requester_email: Util.deep_get(compare, [:user, :email], ""),
      embed_code: compare.embed_code,
      embed_time: false,
      frames: 2,
      public: compare.public,
      file_name: "",
      media_urls: %{
        mp4: "#{EvercamMediaWeb.Endpoint.static_url}/#{version}/cameras/#{compare.camera.exid}/compares/#{compare.exid}.mp4",
        gif: "#{EvercamMediaWeb.Endpoint.static_url}/#{version}/cameras/#{compare.camera.exid}/compares/#{compare.exid}.gif"
      },
      type: "compare",
      thumbnail_url: "#{EvercamMediaWeb.Endpoint.static_url}/#{version}/cameras/#{compare.camera.exid}/archives/#{compare.exid}/thumbnail?type=compare"
    }
  end

  defp date_wrt_version("v2", date, camera), do: Util.datetime_to_iso8601(date, Camera.get_timezone(camera))
  defp date_wrt_version("v1", date, _camera), do: Util.ecto_datetime_to_unix(date)

  defp status(0), do: "Processing"
  defp status(1), do: "Completed"
  defp status(2), do: "Failed"
end
