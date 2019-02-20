defmodule Evercam.Repo.Migrations.AddUrlFieldInArchive do
  use Ecto.Migration

  def change do
    alter table(:archives) do
      add :url, :string
    end
  end
end
