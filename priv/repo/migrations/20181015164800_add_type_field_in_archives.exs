defmodule Evercam.Repo.Migrations.AddTypeFieldInArchives do
  use Ecto.Migration

  def change do
    alter table(:archives) do
      add :type, :string
    end
  end
end
