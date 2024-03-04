defmodule Y.Content.Binary do
  alias __MODULE__
  defstruct content: <<>>

  def new(content), do: %Binary{content: content}
end
