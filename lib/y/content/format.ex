defmodule Y.Content.Format do
  alias __MODULE__
  defstruct [:key, :value]

  def new(k, v), do: %Format{key: k, value: v}
  def to_map(%Format{key: key, value: value}), do: %{key => value}
end
