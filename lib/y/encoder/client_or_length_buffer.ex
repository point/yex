defmodule Y.Encoder.ClientOrLengthBuffer do
  alias __MODULE__

  defstruct buffer: <<>>, s: 0, count: 0

  import Y.Encoder.Operations

  def new, do: %ClientOrLengthBuffer{}

  def write(%ClientOrLengthBuffer{s: s, count: count} = b, v) when s == v do
    %{b | count: count + 1}
  end

  def write(%ClientOrLengthBuffer{} = b, v) do
    %{flush(b) | count: 1, s: v}
  end

  def flush(%ClientOrLengthBuffer{s: s, count: count, buffer: buffer} = b) when count > 0 do
    buf =
      buffer
      |> write_int(if count == 1, do: s, else: -s)
      |> then(fn buf -> if count > 1, do: write_uint(buf, count - 2), else: buf end)

    %{b | buffer: buf}
  end

  def flush(b), do: b

  defimpl Y.Encoder.Bufferable do
    def dump(%ClientOrLengthBuffer{} = b) do
      Y.Encoder.ClientOrLengthBuffer.flush(b).buffer
    end
  end
end
