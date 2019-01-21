defmodule Vendor do
  use EvercamMediaWeb, :model
  import Ecto.Query
  alias EvercamMedia.Repo

  schema "vendors" do
    has_many :vendor_models, VendorModel, foreign_key: :vendor_id

    field :exid, :string
    field :name, :string
    field :known_macs, EvercamMedia.Types.JSON
  end

  def by_exid_without_associations(exid) do
    Vendor
    |> where(exid: ^String.downcase(exid))
    |> Repo.one
  end

  def by_exid(exid) do
    Vendor
    |> where(exid: ^String.downcase(exid))
    |> preload(:vendor_models)
    |> Repo.one
  end

  def get_models_count(vendor) do
    case vendor.vendor_models do
      nil -> 0
      vendor_models -> Enum.count(vendor_models)
    end
  end

  def get_all(query \\ Vendor) do
    query
    |> Repo.all
  end

  def with_exid_if_given(query, nil), do: query
  def with_exid_if_given(query, exid) do
    query
    |> where([v], v.exid == ^String.downcase(exid))
  end

  def with_name_if_given(query, nil), do: query
  def with_name_if_given(query, name) do
    query
    |> where([v], like(v.name, ^name))
  end

  def with_known_macs_if_given(query, nil), do: query
  def with_known_macs_if_given(query, mac_address) do
    mac_address = String.upcase(mac_address)
    query
    |> where([v], fragment("? @> ARRAY[?]", v.known_macs, ^mac_address))
  end
end
