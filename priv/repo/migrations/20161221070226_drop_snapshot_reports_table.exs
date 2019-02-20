defmodule Evercam.Repo.Migrations.DropSnapshotReportsTable do
  use Ecto.Migration

  def change do
    drop table(:snapshot_reports)
  end
end
