defmodule EvercamMediaWeb.SnapshotExtractorView do
  use EvercamMediaWeb, :view
  alias EvercamMedia.Util

  def render("index.json", %{snapshot_extractor: snapshot_extractors, version: version}) do
    %{SnapshotExtractor: render_many(snapshot_extractors, __MODULE__, "snapshot_extractor.#{version}.json")}
  end

  def render("show.json", %{snapshot_extractor: snapshot_extractor, version: version}) do
    %{SnapshotExtractor: render_many([snapshot_extractor], __MODULE__, "snapshot_extractor.#{version}.json")}
  end

  def render("snapshot_extractor.v1.json", %{snapshot_extractor: snapshot_extractor}) do
    %{
      id: snapshot_extractor.id,
      camera: snapshot_extractor.camera.name,
      from_date: Util.ecto_datetime_to_unix(snapshot_extractor.from_date),
      to_date: Util.ecto_datetime_to_unix(snapshot_extractor.to_date),
      interval: snapshot_extractor.interval,
      schedule: snapshot_extractor.schedule,
      status: snapshot_extractor.status,
      requestor: snapshot_extractor.requestor,
      created_at: Util.ecto_datetime_to_unix(snapshot_extractor.created_at),
      updated_at: Util.ecto_datetime_to_unix(snapshot_extractor.updated_at)
    }
  end
  def render("snapshot_extractor.v2.json", %{snapshot_extractor: snapshot_extractor}) do
    %{
      id: snapshot_extractor.id,
      camera: snapshot_extractor.camera.name,
      from_date: Util.datetime_to_iso8601(snapshot_extractor.from_date, Camera.get_timezone(snapshot_extractor.camera)),
      to_date: Util.datetime_to_iso8601(snapshot_extractor.to_date, Camera.get_timezone(snapshot_extractor.camera)),
      interval: snapshot_extractor.interval,
      schedule: snapshot_extractor.schedule,
      status: snapshot_extractor.status,
      requestor: snapshot_extractor.requestor,
      created_at: Util.datetime_to_iso8601(snapshot_extractor.created_at, Camera.get_timezone(snapshot_extractor.camera)),
      updated_at: Util.datetime_to_iso8601(snapshot_extractor.updated_at, Camera.get_timezone(snapshot_extractor.camera))
    }
  end
end
