defmodule Evercam.Repo.Migrations.AddInsightFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :insight_id, :text
      add :insight_auth_key, :text
    end
  end
end
