defmodule Evercam.Repo.Migrations.AddIsPausedTimezoneToSnapmails do
  use Ecto.Migration

  def change do
    alter table(:snapmails) do
      add :timezone, :text
      add :is_paused, :boolean, null: false, default: false
    end
  end
end
