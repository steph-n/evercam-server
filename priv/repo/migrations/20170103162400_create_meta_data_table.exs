defmodule Evercam.Repo.Migrations.CreateMetaData do
  use Ecto.Migration

  def up do
    create table(:meta_datas) do
      add :user_id, references(:users, on_delete: :nothing)
      add :camera_id, references(:cameras, on_delete: :nothing)
      add :action, :text, null: false
      add :process_id, :integer
      add :extra, :json

      timestamps
    end
  end

  def down do
    drop table(:meta_datas)
  end
end
