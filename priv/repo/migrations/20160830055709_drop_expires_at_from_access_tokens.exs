defmodule Evercam.Repo.Migrations.DropExpiresAtFromAccessTokens do
  use Ecto.Migration

  def change do
    alter table(:access_tokens) do
      remove :expires_at
    end
  end
end
