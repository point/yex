defmodule Y.Encoder.StringBuffer do
  alias __MODULE__
  alias Y.Encoder.ClientOrLengthBuffer

  defstruct buffer: <<>>, lens: ClientOrLengthBuffer.new()

  import Y.Encoder.Operations

  def new, do: %StringBuffer{}

  def write(%StringBuffer{buffer: buffer, lens: lens} = b, string) when is_bitstring(string) do
    %{b | buffer: buffer <> string, lens: ClientOrLengthBuffer.write(lens, String.length(string))}
  end

  defimpl Y.Encoder.Bufferable do
    def dump(%StringBuffer{} = b) do
      write_string(b.buffer) <>
        Y.Encoder.Bufferable.dump(b.lens)
    end
  end
end
