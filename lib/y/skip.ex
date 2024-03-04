defmodule Y.Skip do
  alias __MODULE__
  alias Y.ID

  defstruct id: %ID{}, length: 0

  def new(%ID{} = id, length), do: %Skip{id: id, length: length}
end
