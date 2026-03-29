defmodule Argus.Accounts.Scope do
  @moduledoc """
  Carries the authenticated caller through context boundaries.

  The scope currently stores the user. Keeping it explicit makes authorization, logging, and
  PubSub scoping easier to extend without passing raw user structs through every public API.
  """

  alias Argus.Accounts.User

  defstruct user: nil

  @doc """
  Builds a scope for the given user, or returns nil.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil
end
