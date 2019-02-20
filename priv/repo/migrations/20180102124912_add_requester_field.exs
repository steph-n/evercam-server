defmodule Evercam.Repo.Migrations.AddRequesterField do
  use Ecto.Migration

  def change do
    alter table(:compares) do
      add :requested_by, references(:users, on_delete: :nothing), null: false
    end
  end
end
