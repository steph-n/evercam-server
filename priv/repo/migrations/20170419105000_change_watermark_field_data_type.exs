defmodule Evercam.Repo.Migrations.ChangeWatermarkFieldDataType do
  use Ecto.Migration

  def change do
    alter table(:timelapses) do
      modify :watermark_logo, :text
    end
  end
end
