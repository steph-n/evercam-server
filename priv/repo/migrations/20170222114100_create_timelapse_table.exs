defmodule Evercam.Repo.Migrations.CreateTimelapseTable do
  use Ecto.Migration

  def up do
    create table(:timelapses) do
      add :camera_id, references(:cameras, on_delete: :nothing), null: false
      add :exid, :string, null: false
      add :title, :string, null: false
      add :frequency, :int, null: false
      add :snapshot_count, :int, default: 0
      add :resolution, :string
      add :status, :int, null: false
      add :date_always, :boolean, default: false
      add :from_datetime, :datetime
      add :time_always, :boolean, default: false
      add :to_datetime, :datetime
      add :watermark_logo, :string
      add :watermark_position, :string
      add :recreate_hls, :boolean, default: false
      add :start_recreate_hls, :boolean, default: false
      add :hls_created, :boolean, default: false
      add :last_snapshot_at, :datetime

      timestamps
    end
    create unique_index :timelapses, [:exid], name: :timelapse_exid_unique_index
  end

  def down do
    drop table(:timelapses)
  end
end
