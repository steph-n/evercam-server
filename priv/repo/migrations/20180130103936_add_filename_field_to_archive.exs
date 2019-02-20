defmodule Evercam.Repo.Migrations.AddFilenameFieldToArchive do
  use Ecto.Migration

  def change do
    alter table(:archives) do
      add :file_name, :string
    end
  end
end
