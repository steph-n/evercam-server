defmodule UserTest do
  use EvercamMedia.ModelCase

  setup do
    {:ok, params: %{username: "johndoe", password: "johndoe", firstname: "John", lastname: "Doe"}}
  end

  test "email validation is correct", %{params: params} do
    refute User.changeset(%User{}, params).valid?
    refute User.changeset(%User{}, Map.merge(params, %{email: nil})).valid?
    refute User.changeset(%User{}, Map.merge(params, %{email: ""})).valid?
    refute User.changeset(%User{}, Map.merge(params, %{email: "spa ces@example.com"})).valid?

    assert User.changeset(%User{}, Map.merge(params, %{email: "regular@example.com"})).valid?
    assert User.changeset(%User{}, Map.merge(params, %{email: "no_dot_in_domain@example"})).valid? == false
    assert User.changeset(%User{}, Map.merge(params, %{email: "unicode@はじめよう.みんな"})).valid? == false
    assert User.changeset(%User{}, Map.merge(params, %{email: "plus+-minus@example.com"})).valid? == true
  end

  test "firstname and lastname is correct", %{params: params} do
    params = Map.merge(params, %{email: "test@local.com"})

    refute User.changeset(%User{}, Map.merge(params, %{firstname: nil, lastname: nil})).valid?
    refute User.changeset(%User{}, Map.merge(params, %{firstname: "  ", lastname: "  "})).valid?
    refute User.changeset(%User{}, Map.merge(params, %{firstname: "Steve", lastname: "  "})).valid?
    refute User.changeset(%User{}, Map.merge(params, %{firstname: "  ", lastname: "O connel"})).valid?

    assert User.changeset(%User{}, Map.merge(params, %{firstname: " Steve", lastname: "O' Connel "})).valid?
    assert User.changeset(%User{}, Map.merge(params, %{firstname: "O' .bert Stain", lastname: " Connel"})).valid?
    assert User.changeset(%User{}, Map.merge(params, %{firstname: "O' .bert Stain", lastname: "Connel .P"})).valid?
  end
end
