defmodule Evercam.Repo.Migrations.AddSnapmailLogsTable do
  use Ecto.Migration

  def up do
    create table(:snapmail_logs) do
      add :recipients, :text
      add :subject, :text
      add :body, :text
      add :image_timestamp, :text

      timestamps()
    end
  end

  def down do
    drop table(:snapmail_logs)
  end
end
