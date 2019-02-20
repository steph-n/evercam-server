defmodule EvercamMedia.ReleaseMigration do
  def run do
    {:ok, _} = Application.ensure_all_started(:evercam_media)

    path = Application.app_dir(:evercam_media, "priv/repo/migrations")

    Ecto.Migrator.run(Evercam.Repo, path, :up, all: true)

    :init.stop()
  end
end
