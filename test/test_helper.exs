ExUnit.configure(exclude: [skip: true])
ExUnit.start
Ecto.Adapters.SQL.Sandbox.mode(Evercam.Repo, :manual)
Ecto.Adapters.SQL.Sandbox.mode(Evercam.SnapshotRepo, :manual)
