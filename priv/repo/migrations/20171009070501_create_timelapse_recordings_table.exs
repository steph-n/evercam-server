defmodule Evercam.Repo.Migrations.CreateTimelapseRecordingsTable do
  use Ecto.Migration

  def up do
    create table(:timelapse_recordings) do
      add :camera_id, references(:cameras, on_delete: :nothing), null: false
      add :frequency, :int, null: false
      add :storage_duration, :int
      add :schedule, :json
      add :status, :string, null: false

      timestamps
    end
  end

  def down do
    drop table(:timelapse_recordings)
  end
end
