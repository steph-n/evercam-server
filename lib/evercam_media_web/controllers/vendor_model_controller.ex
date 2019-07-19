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
          wifi :boolean, ""
          vendor_id :string, ""
          varifocal :boolean, ""
          username :string, ""
          upnp :boolean, ""
          shape :string, ""
          sd_card :boolean, "", default: false
          resolution :string, ""
          ptz :boolean, "", default: false
          psia :boolean, "", default: false
          poe :boolean, "", default: false
          password :string, ""
          onvif :boolean, "", default: false
          official_url :string, ""
          name :string, ""
          mpeg4_url :string, ""
          more_info :string, ""
          mobile_url :string, ""
          mjpg_url :string, ""
          lowres_url :string, ""
          jpg_url :string, ""
          infrared :boolean, "", default: false
          images (Schema.new do
            properties do
              thumbnail :string, ""
              original :string, ""
              icon :string, ""
            end
          end)
          id :string, ""
          h264_url :string, ""
          discontinued :boolean, "", default: false
          defaults (Schema.new do
            properties do
              snapshots (Schema.new do
                properties do
                  mpeg4 :string, ""
                  mobile :string, ""
                  mjpg :string, ""
                  jpg :string, ""
                  h264 :string, ""
                end
              end)
              auth (Schema.new do
                properties do
                  basic (Schema.new do
                    properties do
                      username :string, ""
                      password :string, ""
                    end
                  end)
                end
              end)
            end
          end)
          audio_url :string, ""
          audio_io :boolean, "", default: false
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
  defp get_limit(limit) do
    case to_integer(limit) do
      num when num < 1 -> @default_limit
      num -> num
    end
  end

  defp get_page(page) when page in [nil, ""], do: 0
  defp get_page(page) do
    case to_integer(page) do
      num when num < 0 -> 0
      num -> num
    end
  end

  defp vendor_exists(_conn, vendor_id) when vendor_id in [nil, ""], do: {:ok, nil}
  defp vendor_exists(conn, vendor_id) do
    case Vendor.by_exid_without_associations(vendor_id) do
      nil -> render_error(conn, 404, "Vendor not found.")
      %Vendor{} = vendor -> {:ok, vendor}
    end
  end
end
