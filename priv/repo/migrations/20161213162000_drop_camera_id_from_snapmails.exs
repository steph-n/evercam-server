defmodule Evercam.Repo.Migrations.DropCameraIdFromSnapmails do
  use Ecto.Migration

  def change do
    alter table(:snapmails) do
      remove :camera_id
    end
  end
end
