defmodule Evercam.Repo.Migrations.ComparesTable do
  use Ecto.Migration

  def up do
    create table(:compares) do
      add :exid, :string, null: false
      add :name, :string, null: false
      add :before_date, :utc_datetime, null: false
      add :after_date, :utc_datetime, null: false
      add :embed_code, :string, null: false
      add :create_animation, :boolean, default: false
      add :camera_id, references(:cameras, on_delete: :nothing), null: false

      timestamps()
    end
    create unique_index :compares, [:exid], name: :compare_exid_unique_index
  end

  def down do
    drop table(:compares)
  end
end
