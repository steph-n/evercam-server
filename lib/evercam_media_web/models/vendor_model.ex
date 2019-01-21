defmodule VendorModel do
  use EvercamMediaWeb, :model
  import Ecto.Query
  alias EvercamMedia.Repo

  @required_fields [:exid, :name, :jpg_url, :vendor_id]
  @optional_fields [:username, :password, :h264_url, :mjpg_url, :mpeg4_url, :mobile_url, :lowres_url, :shape, :resolution, :official_url, :more_info, :audio_url, :poe, :wifi, :upnp, :ptz, :infrared, :varifocal, :sd_card, :audio_io, :discontinued, :onvif, :psia, :channel, :updated_at, :created_at]

  schema "vendor_models" do
    belongs_to :vendor, Vendor, foreign_key: :vendor_id
    has_many :cameras, Camera, foreign_key: :model_id

    field :exid, :string
    field :name, :string
    field :username, :string
    field :password, :string
    field :jpg_url, :string
    field :h264_url, :string
    field :mjpg_url, :string
    field :mpeg4_url, :string
    field :mobile_url, :string
    field :lowres_url, :string
    field :shape, :string
    field :resolution, :string
    field :official_url, :string
    field :more_info, :string
    field :audio_url, :string
    field :poe, :boolean
    field :wifi, :boolean
    field :upnp, :boolean
    field :ptz, :boolean
    field :infrared, :boolean
    field :varifocal, :boolean
    field :sd_card, :boolean
    field :audio_io, :boolean
    field :discontinued, :boolean
    field :onvif, :boolean
    field :psia, :boolean
    field :channel, :integer
    timestamps(inserted_at: :created_at, type: :utc_datetime, default: Calendar.DateTime.now_utc)
  end

  def by_exid(exid) do
    VendorModel
    |> where(exid: ^String.downcase(exid))
    |> preload(:vendor)
    |> Repo.one
  end

  def get_vendor_default_model(nil), do: nil
  def get_vendor_default_model(vendor) do
    VendorModel
    |> where(vendor_id: ^vendor.id)
    |> where(name: "Default")
    |> Repo.one
  end

  def get_model(action, vendor_exid, model_exid) do
    vendor_exid = String.downcase("#{vendor_exid}")
    model_exid = String.downcase("#{model_exid}")

    case {vendor_exid, model_exid} do
      {"", ""} ->
        if action == "update", do: nil, else: by_exid("other_default")
      {"", model_exid} ->
        by_exid(model_exid)
      {vendor_exid, ""} ->
        vendor_exid
        |> Vendor.by_exid
        |> get_vendor_default_model
      {vendor_exid, model_exid} ->
        model = by_exid(model_exid)
        if model, do: model, else: get_model(action, vendor_exid, "")
    end
  end

  def get_models_count(query) do
    query
    |> select([vm], count(vm.id))
    |> Repo.all
    |> List.first
  end

  def get_all(query \\ VendorModel) do
    query
    |> order_by([vm], asc: vm.name)
    |> preload(:vendor)
    |> Repo.all
  end

  def check_vendor_in_query(query, vendor) when vendor in [nil, ""], do: query
  def check_vendor_in_query(query, vendor) do
    query
    |> where([vm], vm.vendor_id == ^vendor.id)
  end

  def check_name_in_query(query, name) when name in [nil, ""], do: query
  def check_name_in_query(query, name) do
    query
    |> where([vm], like(fragment("lower(?)", vm.name), ^("%#{String.downcase(name)}%")))
  end

  def get_channel(camera, channel) when channel in ["", nil] do
    camera.vendor_model.jpg_url
    |> String.downcase
    |> String.split("/channels/")
    |> List.last
    |> String.split("/")
    |> List.first
    |> String.to_integer
  end
  def get_channel(_camera, channel), do: channel

  def get_url(model, attr \\ "jpg")
  def get_url(nil, _attr), do: ""
  def get_url(model, "jpg"), do: model.jpg_url
  def get_url(model, "h264"), do: model.h264_url
  def get_url(model, "lowres"), do: model.lowres_url
  def get_url(model, "mpeg4"), do: model.mpeg4_url
  def get_url(model, "mpeg"), do: model.mpeg4_url
  def get_url(model, "mjpg"), do: model.mjpg_url
  def get_url(model, "mobile"), do: model.mobile_url
  def get_url(model, "audio"), do: model.audio_url

  def get_image_url(model_full, type \\ "original") do
    "https://evercam-public-assets.s3.amazonaws.com/#{model_full.vendor.exid}/#{model_full.exid}/#{type}.jpg"
  end

  def changeset(model, params \\ :invalid) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
