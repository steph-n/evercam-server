defmodule Evercam.Repo.Migrations.AddAlertEmailsFieldToCameras do
  use Ecto.Migration

  def change do
    alter table(:cameras) do
      add :alert_emails, :text
    end
  end
end
