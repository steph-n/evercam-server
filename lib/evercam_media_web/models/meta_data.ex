defmodule MetaData do
  use EvercamMediaWeb, :model
  alias EvercamMedia.Repo
  import Ecto.Query

  @required_fields [:action]
  @optional_fields [:camera_id, :user_id, :process_id, :extra]

  schema "meta_datas" do
    belongs_to :camera, Camera
    belongs_to :user, User

    field :action, :string
    field :process_id, :integer
    field :extra, EvercamMedia.Types.JSON
    timestamps(type: :utc_datetime, default: Calendar.DateTime.now_utc)
  end

  def by_camera(camera_id, action \\ "rtmp") do
    MetaData
    |> where(camera_id: ^camera_id)
    |> where(action: ^action)
    |> Repo.one
  end

  def insert_meta(params) do
    meta_changeset = changeset(%MetaData{}, params)
    Repo.insert(meta_changeset)
  end

  def update_requesters(nil, _), do: :noop
  def update_requesters(meta_data, requester) do
    extra = meta_data |> Map.get(:extra)
    case String.contains?(extra["requester"], requester) do
      false ->
        extra = Map.put(extra, "requester", "#{extra["requester"]}, #{requester}")
        meta_params = %{extra: extra}
        changeset(meta_data, meta_params)
        |> Repo.update
      _ -> :noop
    end
  end

  def remove_requesters(nil, _), do: :noop
  def remove_requesters(meta_data, requester) do
    extra = meta_data |> Map.get(:extra)
    requesters =
      extra["requester"]
      |> String.split([", ", ","], trim: true)
      |> Enum.map(fn(user) -> String.trim(user) end)
      |> Enum.reject(fn(user) -> user == requester end)
      |> Enum.join(",")

    extra = extra |> Map.put("requester", requesters)
    meta_params = %{extra: extra}
    changeset(meta_data, meta_params)
    |> Repo.update
  end

  def delete_by_process_id(process_id) do
    MetaData
    |> where(process_id: ^process_id)
    |> Repo.delete_all
  end

  def delete_by_camera_id(camera_id) do
    MetaData
    |> where(camera_id: ^camera_id)
    |> Repo.delete_all
  end

  def delete_by_camera_and_action(camera_id, action) do
    MetaData
    |> where(camera_id: ^camera_id)
    |> where(action: ^action)
    |> Repo.delete_all
  end

  def delete_all do
    MetaData
    |> Repo.delete_all
  end

  def changeset(model, params \\ :invalid) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
