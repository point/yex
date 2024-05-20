defmodule Y.Content.Deleted do
  alias __MODULE__
  alias Y.Item
  defstruct len: 0

  def new(len), do: %Deleted{len: len}
  def from_item(%Item{length: l}), do: %Deleted{len: l}
end
