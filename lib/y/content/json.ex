defmodule Y.Content.JSON do
  alias __MODULE__
  defstruct arr: []

  def new(arr) when is_list(arr), do: %JSON{arr: arr}
end
