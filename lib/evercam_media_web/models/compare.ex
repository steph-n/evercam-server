defmodule Compare do
  use EvercamMediaWeb, :model
  import Ecto.Changeset
  import Ecto.Query
  alias EvercamMedia.Repo

  @required_fields [:camera_id, :name, :before_date, :after_date, :embed_code, :status, :requested_by, :exid]
  @optional_fields [:create_animation, :public]

  # @status %{processing: 0, completed: 1, failed: 2}

  schema "compares" do
    belongs_to :camera, Camera, foreign_key: :camera_id
    belongs_to :user, User, foreign_key: :requested_by

    field :exid, :string
    field :name, :string
    field :before_date, :utc_datetime_usec
    field :after_date, :utc_datetime_usec
    field :embed_code, :string
    field :public, :boolean
    field :create_animation, :boolean
    field :status, :integer, default: 0
    timestamps(type: :utc_datetime_usec, default: Calendar.DateTime.now_utc)
  end

  def get_by_camera(camera_id) do
    Compare
    |> where(camera_id: ^camera_id)
    |> preload(:camera)
    |> preload(:user)
    |> Repo.all
  end

  def by_exid(exid) do
    Compare
    |> where(exid: ^String.downcase(exid))
    |> preload(:camera)
    |> preload(:user)
    |> Repo.one
  end

  def by_status(status) do
    Compare
    |> where(status: ^status)
    |> preload(:camera)
    |> preload(:user)
    |> Repo.all
  end

  def delete_by_exid(exid) do
    Compare
    |> where(exid: ^exid)
    |> Repo.delete_all
  end

  def delete_by_camera(id) do
    Compare
    |> where(camera_id: ^id)
    |> Repo.delete_all
  end

  def get_last_by_camera(camera_id) do
    Compare
    |> where(camera_id: ^camera_id)
    |> preload(:camera)
    |> preload(:user)
    |> order_by(desc: :inserted_at)
    |> limit(1)
    |> Repo.one
  end

  def changeset(model, params \\ :invalid) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
