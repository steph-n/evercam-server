defmodule Evercam.Repo.Migrations.DropInsightAuthKeyFromUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :insight_auth_key
    end
  end
end
