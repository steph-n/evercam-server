defmodule EvercamMedia.UpdateModelUrls do
  require Logger
  alias EvercamMedia.Util
  alias Evercam.Repo

  def update_urls do
    VendorModel.get_all
    |> Enum.each(fn(model) ->
      Logger.debug "Start data coping for model: #{model.name}"
      update_params =
        %{}
        |> add_parameter("field", "jpg_url", Util.deep_get(model.config, ["snapshots", "jpg"], ""))
        |> add_parameter("field", "h264_url", Util.deep_get(model.config, ["snapshots", "h264"], ""))
        |> add_parameter("field", "mjpg_url", Util.deep_get(model.config, ["snapshots", "mjpg"], ""))
        |> add_parameter("field", "mpeg4_url", Util.deep_get(model.config, ["snapshots", "mpeg4"], ""))
        |> add_parameter("field", "mobile_url", Util.deep_get(model.config, ["snapshots", "mobile"], ""))
        |> add_parameter("field", "lowres_url", Util.deep_get(model.config, ["snapshots", "lowres"], ""))
        |> add_parameter("field", "username", Util.deep_get(model.config, ["auth", "basic", "username"], ""))
        |> add_parameter("field", "password", Util.deep_get(model.config, ["auth", "basic", "password"], ""))

      model
      |> VendorModel.changeset(update_params)
      |> Repo.update
    end)
  end

  defp add_parameter(params, _field, _key, nil), do: params
  defp add_parameter(params, "field", key, value) do
    case value do
      nil -> Map.put(params, key, "")
      "null" -> Map.put(params, key, "")
      _ -> Map.put(params, key, value)
    end
  end
end
