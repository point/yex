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
      if count == 1 do
        # Single value: write as positive
        write_int(buffer, s)
      else
        # Multiple values: write as negative (with sign bit set) + count
        # Use write_int_with_sign to handle s == 0 case (negative zero)
        buffer
        |> write_int_with_sign(s, true)
        |> write_uint(count - 2)
      end

    %{b | buffer: buf}
  end

  def flush(b), do: b

  defimpl Y.Encoder.Bufferable do
    def dump(%ClientOrLengthBuffer{} = b) do
      Y.Encoder.ClientOrLengthBuffer.flush(b).buffer
    end
  end
end
