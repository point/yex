defmodule Y.Encoder.Buffer do
  alias __MODULE__
  alias Y.Encoder.ClientOrLengthBuffer
  alias Y.Encoder.InfoBuffer
  alias Y.Encoder.ClockBuffer
  alias Y.Encoder.Bufferable
  alias Y.Encoder.StringBuffer

  import Y.Encoder.Operations, only: [write_bitstring: 1, write_uint: 1]

  defstruct rest: <<>>,
            client: ClientOrLengthBuffer.new(),
            info: InfoBuffer.new(),
            left_clock: ClockBuffer.new(),
            right_clock: ClockBuffer.new(),
            parent_info: InfoBuffer.new(),
            string: StringBuffer.new(),
            key: StringBuffer.new(),
            length: ClientOrLengthBuffer.new(),
            type_ref: ClientOrLengthBuffer.new(),
            delete_set_cur_val: 0

  def new(), do: %Buffer{}

  def write(%Buffer{client: cb} = b, :client, client) do
    %{b | client: ClientOrLengthBuffer.write(cb, client)}
  end

  def write(%Buffer{info: ib} = b, :info, info) do
    %{b | info: InfoBuffer.write(ib, info)}
  end

  def write(%Buffer{client: cb, left_clock: lc} = b, :left_id, id) do
    %{
      b
      | client: ClientOrLengthBuffer.write(cb, id.client),
        left_clock: ClockBuffer.write(lc, id.clock)
    }
  end

  def write(%Buffer{client: cb, right_clock: rc} = b, :right_id, id) do
    %{
      b
      | client: ClientOrLengthBuffer.write(cb, id.client),
        right_clock: ClockBuffer.write(rc, id.clock)
    }
  end

  def write(%Buffer{parent_info: ib} = b, :parent_info, info) do
    %{b | parent_info: InfoBuffer.write(ib, info)}
  end

  def write(%Buffer{length: lb} = b, :length, len) do
    %{b | length: ClientOrLengthBuffer.write(lb, len)}
  end

  def write(%Buffer{string: sb} = b, :string, str) do
    %{b | string: StringBuffer.write(sb, str)}
  end

  def write(%Buffer{key: kb} = b, :key, key_str) do
    %{b | key: StringBuffer.write(kb, key_str)}
  end

  def write(%Buffer{} = b, :ds_clock, clock) do
    diff = clock - b.delete_set_cur_val
    %{b | delete_set_cur_val: clock} |> write(:rest, write_uint(diff))
  end

  def write(%Buffer{} = b, :ds_length, length) do
    %{b | delete_set_cur_val: b.delete_set_cur_val + length}
    |> write(:rest, write_uint(length - 1))
  end

  def write(%Buffer{type_ref: tr} = b, :type_ref, ref) do
    %{b | type_ref: ClientOrLengthBuffer.write(tr, ref)}
  end

  def write(%Buffer{} = b, key, what) do
    existing = Map.fetch!(b, key)
    %{b | key => existing <> what}
  end

  def reset_delete_set_current_value(%Buffer{} = b), do: %{b | delete_set_cur_val: 0}

  def dump(%Buffer{} = b) do
    key_clock = <<>>

    <<0>>
    |> Kernel.<>(write_bitstring(key_clock))
    |> Kernel.<>(Bufferable.dump(b.client) |> write_bitstring())
    |> Kernel.<>(Bufferable.dump(b.left_clock) |> write_bitstring())
    |> Kernel.<>(Bufferable.dump(b.right_clock) |> write_bitstring())
    |> Kernel.<>(Bufferable.dump(b.info) |> write_bitstring())
    |> Kernel.<>(Bufferable.dump(b.string) |> write_bitstring())
    |> Kernel.<>(Bufferable.dump(b.parent_info) |> write_bitstring())
    |> Kernel.<>(Bufferable.dump(b.type_ref) |> write_bitstring())
    |> Kernel.<>(Bufferable.dump(b.length) |> write_bitstring())
    |> Kernel.<>(b.rest)
  end

  def dump_rest_only!(%Buffer{} = b), do: b.rest
end

# const encoder = encoding.createEncoder()
# encoding.writeVarUint(encoder, 0) // this is a feature flag that we might use in the future
# encoding.writeVarUint8Array(encoder, this.keyClockEncoder.toUint8Array())
# encoding.writeVarUint8Array(encoder, this.clientEncoder.toUint8Array())
# encoding.writeVarUint8Array(encoder, this.leftClockEncoder.toUint8Array())
# encoding.writeVarUint8Array(encoder, this.rightClockEncoder.toUint8Array())
# encoding.writeVarUint8Array(encoder, encoding.toUint8Array(this.infoEncoder))
# encoding.writeVarUint8Array(encoder, this.stringEncoder.toUint8Array())
# encoding.writeVarUint8Array(encoder, encoding.toUint8Array(this.parentInfoEncoder))
# encoding.writeVarUint8Array(encoder, this.typeRefEncoder.toUint8Array())
# encoding.writeVarUint8Array(encoder, this.lenEncoder.toUint8Array())
# // @note The rest encoder is appended! (note the missing var)
# encoding.writeUint8Array(encoder, encoding.toUint8Array(this.restEncoder))
# return encoding.toUint8Array(encoder)
