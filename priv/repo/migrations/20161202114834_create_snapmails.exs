defmodule Evercam.Repo.Migrations.CreateSnapmail do
  use Ecto.Migration

  def up do
    create table(:snapmails) do
      add :exid, :string, null: false
      add :subject, :string, null: false
      add :recipients, :string
      add :message, :string
      add :notify_days, :string
      add :notify_time, :string, null: false
      add :is_public, :boolean, null: false, default: false
      add :user_id, references(:users, on_delete: :nothing)
      add :camera_id, references(:cameras, on_delete: :nothing), null: false

      timestamps
    end
    create unique_index :snapmails, [:exid], name: :exid_unique_index
  end

  def down do
    drop table(:snapmails)
  end
end
