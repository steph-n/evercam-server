defmodule Evercam.Repo.Migrations.AddIsPublicFieldInCompares do
  use Ecto.Migration

  def change do
    alter table(:compares) do
      add :public, :boolean, default: true
    end
  end
end
