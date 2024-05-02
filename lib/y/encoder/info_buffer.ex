defmodule Y.Encoder.InfoBuffer do
  alias __MODULE__
  defstruct buffer: <<>>, s: nil, count: 0
  import Y.Encoder.Operations

  def new, do: %InfoBuffer{}

  def write(%InfoBuffer{s: s, count: count} = b, v) when s == v do
    %{b | count: count + 1}
  end

  def write(%InfoBuffer{count: count, buffer: buffer} = b, v) do
    buf =
      if count > 0 do
        write_uint(buffer, count - 1)
      else
        buffer
      end <>
        write_byte(v)

    %{b | buffer: buf, count: 1, s: v}
  end

  defimpl Y.Encoder.Bufferable do
    def dump(%InfoBuffer{buffer: buffer}) do
      buffer
    end
  end
end
