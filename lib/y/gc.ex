defmodule Y.GC do
  alias __MODULE__
  alias Y.ID
  alias Y.Item

  defstruct id: %ID{}, length: 0

  def new(%ID{} = id, length), do: %GC{id: id, length: length}

  def from_item(%Item{id: i_id, length: i_length}), do: %GC{id: i_id, length: i_length}
end
