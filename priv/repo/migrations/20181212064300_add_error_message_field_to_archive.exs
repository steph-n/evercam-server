defmodule Evercam.Repo.Migrations.AddErrorMessageFieldToArchive do
  use Ecto.Migration

  def change do
    alter table(:archives) do
      add :error_message, :text
    end
  end
end
