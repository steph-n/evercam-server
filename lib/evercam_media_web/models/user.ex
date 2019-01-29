defmodule User do
  use EvercamMediaWeb, :model
  import Ecto.Query
  alias EvercamMedia.Repo

  @email_regex ~r/^(?!.*\.{2})[a-z0-9._-]+@[a-z\d\-]+(\.[a-z]+)*\.[a-z]+\z/
  @name_regex ~r/^[\p{Xwd}\s,.']+$/

  @required_fields [:password, :firstname, :lastname, :email]
  @optional_fields [:username, :telegram_username, :referral_url, :api_id, :api_key, :reset_token, :token_expires_at, :payment_method, :country_id, :confirmed_at, :updated_at, :last_login_at, :created_at]

  schema "users" do
    belongs_to :country, Country, foreign_key: :country_id
    has_many :cameras, Camera, foreign_key: :owner_id
    has_many :camera_shares, CameraShare
    has_one :access_tokens, AccessToken

    field :username, :string
    field :telegram_username, :string
    field :referral_url, :string
    field :password, :string
    field :firstname, :string
    field :lastname, :string
    field :email, :string
    field :api_id, :string
    field :api_key, :string
    field :reset_token, :string
    field :token_expires_at, :utc_datetime
    field :stripe_customer_id, :string
    field :confirmed_at, :utc_datetime
    field :last_login_at, :utc_datetime
    field :payment_method, :integer
    timestamps(inserted_at: :created_at, type: :utc_datetime, default: Calendar.DateTime.now_utc)
  end

  def invalidate_auth(api_id, api_key) do
    ConCache.delete(:users, "#{api_id}_#{api_key}")
  end

  def invalidate_share_users(%User{} = user) do
    CameraShare
    |> where([cs], cs.user_id == ^user.id or cs.sharer_id == ^user.id)
    |> preload(:camera)
    |> preload([camera: :owner])
    |> Repo.all
    |> Enum.map(fn(cs) -> cs.camera.owner end)
    |> Enum.uniq
    |> Enum.each(fn(user) -> Camera.invalidate_user(user) end)
  end

  def get_by_api_keys("", ""), do: nil
  def get_by_api_keys(nil, _api_key), do: nil
  def get_by_api_keys(_api_id, nil), do: nil
  def get_by_api_keys(api_id, api_key) do
    ConCache.dirty_get_or_store(:users, "#{api_id}_#{api_key}", fn() ->
      by_api_keys(api_id, api_key)
    end)
  end

  def by_username_or_email(login) when login in["", nil], do: nil
  def by_username_or_email(login) do
    login = String.downcase(login)
    User
    |> where([u], fragment("lower(?)", u.username) == ^login or fragment("lower(?)", u.email) == ^login)
    |> preload(:country)
    |> Repo.one
  end

  def by_telegram_username(login) when login in["", nil], do: nil
  def by_telegram_username(login) do
    login = String.downcase(login)
    User
    |> where([u], fragment("lower(?)", u.telegram_username) == ^login)
    |> preload(:country)
    |> Repo.one
  end

  def by_username(username) do
    User
    |> where(username: ^String.downcase(username))
    |> preload(:country)
    |> Repo.one
  end

  def by_api_keys(api_id, api_key) do
    User
    |> where(api_id: ^api_id)
    |> where(api_key: ^api_key)
    # |> preload(:access_tokens)
    |> Repo.one
  end

  def with_access_to(camera_full) do
    User
    |> join(:inner, [u], cs in CameraShare)
    |> where([_, cs], cs.camera_id == ^camera_full.id)
    |> where([u, cs], u.id == cs.user_id)
    |> Repo.all
    |> Enum.concat([camera_full.owner])
  end

  def get_country_attr(user, attr) do
    case user.country do
      nil -> ""
      country -> Map.get(country, attr)
    end
  end

  def get_fullname(nil), do: ""
  def get_fullname(user) do
    "#{user.firstname} #{user.lastname}"
  end

  def get_user_from_token(token) do
    token = AccessToken.by_request_token(token)
    cond do
      nil == token -> nil
      user = token.user -> user
      grantor = token.grantor -> grantor
      true -> token
    end
  end

  def delete_by_id(user_id) do
    User
    |> where(id: ^user_id)
    |> Repo.delete_all
  end

  defp encrypt_password(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(changeset, :password, hash_password(password))
      _ ->
        changeset
    end
  end

  def hash_password(password) do
    Comeonin.Bcrypt.hashpass(password, Comeonin.Bcrypt.gen_salt(12, true))
  end

  def has_username(changeset) do
    case get_field(changeset, :username) do
      username when username in [nil, ""] -> put_change(changeset, :username, get_field(changeset, :email))
      _ ->
        changeset
        |> put_change(:username, get_field(changeset, :email))
        |> update_change(:username, &String.downcase/1)
    end
  end

  def changeset(model, params \\ :invalid) do
    model
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> has_username
    |> unique_constraint(:email, [name: :user_email_unique_index, message: "Email has already been taken."])
    |> unique_constraint(:username, [name: :user_username_unique_index, message: "Username has already been taken."])
    |> validate_format(:firstname, @name_regex)
    |> validate_format(:lastname, @name_regex)
    |> update_change(:email, &String.downcase/1)
    |> validate_format(:email, @email_regex, [message: "Email format isn't valid!"])
    |> validate_length(:password, [min: 6, message: "Password should be at least 6 character(s)."])
    |> encrypt_password
    |> update_change(:firstname, &String.trim/1)
    |> update_change(:lastname, &String.trim/1)
    |> validate_length(:firstname, [min: 2, message: "Firstname should be at least 2 character(s)."])
    |> validate_length(:lastname, [min: 2, message: "Lastname should be at least 2 character(s)."])
  end
end
