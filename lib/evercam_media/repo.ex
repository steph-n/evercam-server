defmodule EvercamMedia.Repo do
  use Ecto.Repo,
    otp_app: :evercam_media,
    adapter: Ecto.Adapters.Postgres

  defmodule NewRelic do
    use Elixir.NewRelic.Plug.Repo, repo: EvercamMedia.Repo
  end
end

defmodule EvercamMedia.SnapshotRepo do
  use Ecto.Repo,
    otp_app: :evercam_media,
    adapter: Ecto.Adapters.Postgres
  require Ecto.Query

  def existss?(queryable) do
    queryable
    |> Ecto.Query.from(select: 1, limit: 1)
    |> Ecto.Queryable.to_query
    |> EvercamMedia.SnapshotRepo.one
    |> case do
      1 -> true
      _ -> false
    end
  end
end
