defmodule Evercam.Repo.Migrations.ChangeDataTypesSnapmails do
  use Ecto.Migration

  def change do
    alter table(:snapmails) do
      modify :recipients, :text
      modify :subject, :text
      modify :message, :text
    end
  end
end
