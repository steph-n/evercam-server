defmodule Evercam.Repo.Migrations.CreateSnapmailCameras do
  use Ecto.Migration

  def up do
    create table(:snapmail_cameras) do
      add :snapmail_id, references(:snapmails, on_delete: :nothing), null: false
      add :camera_id, references(:cameras, on_delete: :nothing), null: false

      timestamps
    end
    create unique_index :snapmail_cameras, [:snapmail_id, :camera_id], name: :snapemail_camera_id_unique_index
  end

  def down do
    drop table(:snapmail_cameras)
  end
end
