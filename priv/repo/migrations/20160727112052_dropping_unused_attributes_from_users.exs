defmodule Evercam.Repo.Migrations.DroppingUnusedAttributesFromUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      remove :billing_id
      remove :is_admin
    end
  end
end
