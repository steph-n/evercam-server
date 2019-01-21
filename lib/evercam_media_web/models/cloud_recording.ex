defmodule CloudRecording do
  use EvercamMediaWeb, :model
  import Ecto.Query
  alias EvercamMedia.Repo

  @required_fields [:camera_id, :frequency, :storage_duration, :status, :schedule]

  schema "cloud_recordings" do
    belongs_to :camera, Camera, foreign_key: :camera_id

    field :frequency, :integer
    field :storage_duration, :integer
    field :status, :string
    field :schedule, EvercamMedia.Types.JSON
  end

  def get_all_ephemeral do
    CloudRecording
    |> where([cl], cl.storage_duration != -1)
    |> preload(:camera)
    |> Repo.all
  end

  def by_camera_id(camera_id) do
    CloudRecording
    |> where(camera_id: ^camera_id)
    |> where([cl], cl.storage_duration != -1)
    |> preload(:camera)
    |> Repo.one
  end

  def delete_by_camera_id(camera_id) do
    CloudRecording
    |> where(camera_id: ^camera_id)
    |> Repo.delete_all
  end

  def schedule(cloud_recording) do
    if cloud_recording == nil || cloud_recording.status == "off" do
      %{}
    else
      cloud_recording.schedule
    end
  end

  def recording(cloud_recording) do
    if cloud_recording == nil do
      "off"
    else
      cloud_recording.status
    end
  end

  def storage_duration(cloud_recording) do
    case cloud_recording do
      nil -> nil
      cr -> cr.storage_duration
    end
  end

  def initial_sleep(cloud_recording) do
    if cloud_recording == nil || cloud_recording.frequency == 1 || cloud_recording.status == "off" do
      :rand.uniform(60) * 1000
    else
      1000
    end
  end

  def sleep(cloud_recording) do
    if cloud_recording == nil || cloud_recording.status == "off" || cloud_recording.status == "paused" do
      60_000
    else
      count_sleep(cloud_recording.frequency)
    end
  end

  defp count_sleep(frequency) when frequency in [5, 10], do: 60_000 * frequency
  defp count_sleep(frequency), do: div(60_000, frequency)

  def changeset(model, params \\ :invalid) do
    model
    |> cast(params, @required_fields)
    |> validate_required(@required_fields)
  end
end
