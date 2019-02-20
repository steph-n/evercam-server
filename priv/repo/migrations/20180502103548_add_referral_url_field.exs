defmodule Evercam.Repo.Migrations.AddReferralUrlField do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :referral_url, :string
    end
  end
end
