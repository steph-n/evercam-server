defmodule Evercam.Repo.Migrations.AddUniqueIndexes do
  use Ecto.Migration

  def change do
    create unique_index :users, [:email], name: :user_email_unique_index
    create unique_index :users, [:username], name: :user_username_unique_index
    create unique_index :countries, [:iso3166_a2], name: :country_code_unique_index
  end
end
