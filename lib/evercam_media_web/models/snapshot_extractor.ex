defmodule SnapshotExtractor do
  use EvercamMediaWeb, :model
  import Ecto.Changeset
  import Ecto.Query
  alias EvercamMedia.Repo

  @required_fields [:camera_id, :to_date, :from_date, :status, :interval, :schedule]
  @optional_fields [:notes, :requestor, :updated_at, :created_at, :create_mp4, :jpegs_to_dropbox, :inject_to_cr]

  schema "snapshot_extractors" do
    belongs_to :camera, Camera, foreign_key: :camera_id

    field :from_date, :utc_datetime, default: Calendar.DateTime.now_utc
    field :to_date, :utc_datetime, default: Calendar.DateTime.now_utc
    field :interval, :integer
    field :schedule, EvercamMedia.Types.JSON
    field :status, :integer
    field :notes, :string
    field :requestor, :string
    field :create_mp4, :boolean
    field :jpegs_to_dropbox, :boolean
    field :inject_to_cr, :boolean
    timestamps(inserted_at: :created_at, type: :utc_datetime, default: Calendar.DateTime.now_utc)
  end

  def by_id(id) do
    SnapshotExtractor
    |> where(id: ^id)
    |> preload(:camera)
    |> Repo.one
  end

  def update_snapshot_extactor(snapshot_extactor, params) do
    snapshot_extactor_changeset = changeset(snapshot_extactor, params)
    case Repo.update(snapshot_extactor_changeset) do
      {:ok, extractor} ->
        full_extractor = Repo.preload(extractor, :camera)
        {:ok, full_extractor}
      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def by_status(status) do
    SnapshotExtractor
    |> where(status: ^status)
    |> order_by([c], desc: c.created_at)
    |> preload(:camera)
    |> Repo.all
  end

  def delete_by_camera_id(camera_id) do
    SnapshotExtractor
    |> where(camera_id: ^camera_id)
    |> Repo.delete_all
  end

  def delete_by_id(id) do
    SnapshotExtractor
    |> where(id: ^id)
    |> Repo.delete_all
  end

  def changeset(snapshot_extractor, params \\ :invalid) do
    snapshot_extractor
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
