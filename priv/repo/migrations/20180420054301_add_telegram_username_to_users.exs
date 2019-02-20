defmodule Evercam.Repo.Migrations.AddTelegramUsernameToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :telegram_username, :string
    end
  end
end
