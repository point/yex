defmodule Y.Content.String do
  alias __MODULE__
  defstruct [:str]

  def new(str) when is_bitstring(str), do: %String{str: str}
  def new(lst) when is_list(lst), do: %String{str: Enum.join(lst)}
end
