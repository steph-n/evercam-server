defmodule EvercamMediaWeb.VendorModelController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger
  import String, only: [to_integer: 1]

  @default_limit 25

  def swagger_definitions do
    %{
      Model: swagger_schema do
        title "Model"
        description ""
        properties do
          id :integer, ""
          vendor_id :integer, "", format: "text"
          name :string, "", format: "text"
          config :string, "", format: "json"
          exid :string, "", format: "text"
          jpg_url :string, "", format: "text"
          h264_url :string, "", format: "text"
          mjpg_url :string, "", format: "text"
          shape :string, "", format: "text"
          resolution :string, "", format: "text"
          official_url :string, "", format: "text"
          more_info :string, "", format: "text"
          poe :boolean, "", default: false
          wifi :boolean, "", default: false
          onvif :boolean, "", default: false
          psia :boolean, "", default: false
          ptz :boolean, "", default: false
          infrared :boolean, "", default: false
          varifocal :boolean, "", default: false
          sd_card :boolean, "", default: false
          upnp :boolean, "", default: false
          audio_io :boolean, "", default: false
          discontinued :boolean, "", default: false
          username :string, "", format: "text"
          password :string, "", format: "text"
          channel :integer, ""
          created_at :string, "", format: "timestamp"
          updated_at :string, "", format: "timestamp"
        end
      end
    }
  end

  swagger_path :index do
    get "/models"
    summary "Returns set of known models for a supported camera vendor."
    parameters do
      vendor_id :query, :string, "Unique identifier for the vendor."
      name :query, :string, "The name of the model."
      limit :query, :string, ""
      page :query, :string, ""
    end
    tag "Models"
    response 200, "Success"
  end

  def index(conn, params) do
    with {:ok, vendor} <- vendor_exists(conn, params["vendor_id"])
    do
      limit = get_limit(params["limit"])
      page = get_page(params["page"])

      models =
        VendorModel
        |> VendorModel.check_vendor_in_query(vendor)
        |> VendorModel.check_name_in_query(params["name"])
        |> VendorModel.get_all

      total_models = Enum.count(models)
      total_pages = Float.floor(total_models / limit)
      returned_models = Enum.slice(models, page * limit, limit)

      render(conn, "index.json", %{vendor_models: returned_models, pages: total_pages, records: total_models})
    end
  end

  swagger_path :show do
    get "/models/{id}"
    summary "Returns available information for the specified model."
    parameters do
      id :path, :string, "The ID of the model being requested."
    end
    tag "Models"
    response 200, "Success"
    response 404, "Not found"
  end

  def show(conn, %{"id" => exid}) do
    case VendorModel.by_exid(exid) do
      nil ->
        render_error(conn, 404, "Model Not found.")
      model ->
        render(conn, "show.json", %{vendor_model: model})
    end
  end

  defp get_limit(limit) when limit in [nil, ""], do: @default_limit
  defp get_limit(limit), do: if to_integer(limit) < 1, do: @default_limit, else: to_integer(limit)

  defp get_page(page) when page in [nil, ""], do: 0
  defp get_page(page), do: if to_integer(page) < 0, do: 0, else: to_integer(page)

  defp vendor_exists(_conn, vendor_id) when vendor_id in [nil, ""], do: {:ok, nil}
  defp vendor_exists(conn, vendor_id) do
    case Vendor.by_exid_without_associations(vendor_id) do
      nil -> render_error(conn, 404, "Vendor not found.")
      %Vendor{} = vendor -> {:ok, vendor}
    end
  end
end
