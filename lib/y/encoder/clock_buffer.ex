defmodule Y.Encoder.ClockBuffer do
  alias __MODULE__
  defstruct buffer: <<>>, s: 0, count: 0, diff: 0
  import Y.Encoder.Operations

  def new, do: %ClockBuffer{}

  def write(%ClockBuffer{diff: diff, s: s, count: count} = b, v) when diff == v - s do
    %{b | s: v, count: count + 1}
  end

  def write(%ClockBuffer{s: s} = b, v) do
    %{flush(b) | count: 1, diff: v - s, s: v}
  end

  def flush(%ClockBuffer{buffer: buffer, diff: diff, count: count} = b) when count > 0 do
    e_diff = diff * 2 + if count == 1, do: 0, else: 1
    buffer = buffer |> write_int(e_diff)

    buffer = if count > 1, do: write_uint(buffer, count - 2), else: buffer
    %{b | buffer: buffer}
  end

  def flush(b), do: b

  defimpl Y.Encoder.Bufferable do
    def dump(%ClockBuffer{} = b) do
      Y.Encoder.ClockBuffer.flush(b).buffer
    end
  end
end
