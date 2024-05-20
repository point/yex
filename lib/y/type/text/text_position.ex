defmodule Y.Type.Text.TextPosition do
  alias __MODULE__
  defstruct left: nil, right: nil, index: 0, attributes: %{}

  def new(left, right, index, attributes) do
    %TextPosition{left: left, right: right, index: index, attributes: attributes}
  end
end
