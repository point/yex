defmodule Y.Decoder.CSState do
  @enforce_keys [:count, :s, :buf]
  defstruct count: 0, s: 0, buf: <<>>
end

defmodule Y.Decoder.CSDState do
  @enforce_keys [:count, :s, :diff, :buf]
  defstruct count: 0, s: 0, diff: 0, buf: <<>>
end

defmodule Y.Decoder.State do
  alias __MODULE__

  defstruct key_clock: <<>>,
            client: %Y.Decoder.CSState{count: 0, s: 0, buf: <<>>},
            left_clock: %Y.Decoder.CSDState{count: 0, s: 0, diff: 0, buf: <<>>},
            right_clock: %Y.Decoder.CSDState{count: 0, s: 0, diff: 0, buf: <<>>},
            info: %Y.Decoder.CSState{count: 0, s: 0, buf: <<>>},
            string: <<>>,
            parent_info: %Y.Decoder.CSState{count: 0, s: 0, buf: <<>>},
            type_ref: <<>>,
            length: %Y.Decoder.CSState{count: 0, s: 0, buf: <<>>},
            rest: <<>>

  def new(
        key_clock: key_clock,
        client: client,
        left_clock: left_clock,
        right_clock: right_clock,
        info: info,
        string: string,
        parent_info: parent_info,
        type_ref: type_ref,
        length: length,
        rest: rest
      ),
      do:
        %State{
          key_clock: key_clock,
          string: string,
          type_ref: type_ref,
          rest: rest
        }
        |> put_in([Access.key!(:client), Access.key!(:buf)], client)
        |> put_in([Access.key!(:info), Access.key!(:buf)], info)
        |> put_in([Access.key!(:length), Access.key!(:buf)], length)
        |> put_in([Access.key!(:left_clock), Access.key!(:buf)], left_clock)
        |> put_in([Access.key!(:right_clock), Access.key!(:buf)], right_clock)
        |> put_in([Access.key!(:parent_info), Access.key!(:buf)], parent_info)

  def read_and_advance(%State{} = state, key, f) do
    msg = Map.fetch!(state, key)
    {ret, new_msg} = f.(msg)
    {ret, %{state | key => new_msg}}
  end
end
