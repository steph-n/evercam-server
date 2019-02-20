defmodule Evercam.Repo.Migrations.AddOfflineReasonField do
  use Ecto.Migration

  def change do
    alter table(:cameras) do
      add :offline_reason, :string
    end
  end
end
