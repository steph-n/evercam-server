defmodule Evercam.Repo.Migrations.DropSnapshotsTable do
  use Ecto.Migration

  def change do
    drop table(:snapshots)
  end
end
