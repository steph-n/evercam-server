defmodule Evercam.Repo.Migrations.AddStatusFieldInCompares do
  use Ecto.Migration

  def change do
    alter table(:compares) do
      add :status, :int, null: false, default: 0
    end
  end
end
