Postgrex.Types.define(EvercamMedia.PostgresTypes,
                    [
                      {Geo.PostGIS.Extension, library: Geo}
                    ] ++ Ecto.Adapters.Postgres.extensions(),
                    json: Jason)
