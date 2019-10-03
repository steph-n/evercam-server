defmodule EvercamMedia.VendorModelControllerTest do
  use EvercamMediaWeb.ConnCase
  import EvercamMediaWeb.VendorModelView, only: [render: 2]

  setup do
    vendor = Repo.insert!(%Vendor{exid: "vendor0", name: "Vendor XYZ", known_macs: []})
    model =
      %VendorModel{vendor_id: vendor.id, name: "Model XYZ", exid: "model0"}
      |> Repo.insert!
      |> Repo.preload(:vendor)

    {:ok, model: model}
  end

  test "GET /v2/models/:id", %{model: model} do
    response = build_conn() |> get("/v2/models/model0")

    assert response.status == 200
  end

  test "GET /v2/models/:id Model not found" do
    response = build_conn() |> get("/v2/models/model1")

    assert response.status == 404
    assert Jason.decode(response.resp_body) == {:ok, %{"message" => "Model Not found."}}
  end
end
