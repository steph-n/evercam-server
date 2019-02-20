defmodule Evercam.Repo.Migrations.AddExtraAndUseridFieldsToTimelapses do
  use Ecto.Migration

  def change do
    alter table(:timelapses) do
      add :user_id, references(:users, on_delete: :nothing), null: false
      add :extra, :json
    end
  end
end
