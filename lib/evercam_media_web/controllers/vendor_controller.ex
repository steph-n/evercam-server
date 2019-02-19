defmodule EvercamMediaWeb.VendorController do
  use EvercamMediaWeb, :controller
  use PhoenixSwagger

  def swagger_definitions do
    %{
      Vendor: swagger_schema do
        title "Vendor"
        description ""
        properties do
          name :string, ""
          logo :string, ""
          known_macs :list, "", example: ["8C:AE:89", "00:0D:F0", "00:A1:B0"]
          id :string, ""
        end
      end
    }
  end

  swagger_path :show do
    get "/vendors/{id}"
    summary "Returns available information for the specified vendor."
    parameters do
      id :path, :string, "The ID of the vendor being requested."
    end
    tag "Vendors"
    response 200, "Success"
    response 404, "Not found"
  end

  def show(conn, %{"id" => exid}) do
    case Vendor.by_exid(exid) do
      nil ->
        render_error(conn, 404, %{message: "Vendor not found."})
      vendor ->
        render(conn, "show.json", %{vendor: vendor})
    end
  end

  swagger_path :index do
    get "/vendors"
    summary "Returns all known IP hardware vendors."
    parameters do
      id :query, :string, "The ID of the vendor being requested."
      name :query, :string, "The name of the vendor."
      mac :query, :string, "The mac address of the vendor."
    end
    tag "Vendors"
    response 200, "Success"
  end

  def index(conn, params) do
    vendors =
      Vendor
      |> Vendor.with_exid_if_given(params["id"])
      |> Vendor.with_name_if_given(params["name"])
      |> Vendor.with_known_macs_if_given(params["mac"])
      |> Vendor.get_all

    render(conn, "index.json", %{vendors: vendors})
  end
end
