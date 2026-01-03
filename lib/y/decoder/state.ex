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
  import Y.Decoder.Operations
  import Bitwise

  defstruct key_clock: %Y.Decoder.CSState{count: 0, s: 0, buf: <<>>},
            keys: [],
            client: %Y.Decoder.CSState{count: 0, s: 0, buf: <<>>},
            left_clock: %Y.Decoder.CSDState{count: 0, s: 0, diff: 0, buf: <<>>},
            right_clock: %Y.Decoder.CSDState{count: 0, s: 0, diff: 0, buf: <<>>},
            info: %Y.Decoder.CSState{count: 0, s: 0, buf: <<>>},
            string: <<>>,
            string_lengths: %Y.Decoder.CSState{count: 0, s: 0, buf: <<>>},
            parent_info: %Y.Decoder.CSState{count: 0, s: 0, buf: <<>>},
            type_ref: %Y.Decoder.CSState{count: 0, s: 0, buf: <<>>},
            length: %Y.Decoder.CSState{count: 0, s: 0, buf: <<>>},
            rest: <<>>,
            delete_set_cur_val: 0

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
        rest: rest,
        delete_set_cur_val: delete_set_cur_val
      ) do
    {string_length, rest_string} = read_uint(string)
    <<real_string::binary-size(^string_length), string_lengths::binary>> = rest_string

    %State{
      string: real_string,
      rest: rest,
      delete_set_cur_val: delete_set_cur_val,
      keys: []
    }
    |> put_in([Access.key!(:key_clock), Access.key!(:buf)], key_clock)
    |> put_in([Access.key!(:client), Access.key!(:buf)], client)
    |> put_in([Access.key!(:info), Access.key!(:buf)], info)
    |> put_in([Access.key!(:length), Access.key!(:buf)], length)
    |> put_in([Access.key!(:left_clock), Access.key!(:buf)], left_clock)
    |> put_in([Access.key!(:right_clock), Access.key!(:buf)], right_clock)
    |> put_in([Access.key!(:parent_info), Access.key!(:buf)], parent_info)
    |> put_in([Access.key!(:type_ref), Access.key!(:buf)], type_ref)
    |> put_in([Access.key!(:string_lengths), Access.key!(:buf)], string_lengths)
  end

  def read_and_advance(%State{} = state, key, f) do
    msg = Map.fetch!(state, key)
    {ret, new_msg} = f.(msg)
    {ret, %{state | key => new_msg}}
  end

  def read_ds_clock(%State{} = state, f) do
    {clock, new_msg} = f.(Map.fetch!(state, :rest))
    clock = state.delete_set_cur_val + clock
    {clock, %{state | delete_set_cur_val: clock, rest: new_msg}}
  end

  def read_ds_len(%State{} = state, f) do
    {diff, new_msg} = f.(Map.fetch!(state, :rest))
    diff = diff + 1
    {diff, %{state | delete_set_cur_val: state.delete_set_cur_val + diff, rest: new_msg}}
  end

  def reset_ds_cur_val(%State{} = state), do: %{state | delete_set_cur_val: 0}

  def read_client(%State{client: %{count: count, s: s, buf: buf}} = state) do
    {c, s, buf} =
      if count == 0 do
        # Use read_int_with_sign to detect negative zero (RLE-encoded 0)
        {s, is_negative?, buf} = read_int_with_sign(buf)

        {c, buf} =
          if is_negative? do
            {c, buf} = read_uint(buf)
            {c + 2, buf}
          else
            {1, buf}
          end

        {c, s, buf}
      else
        {count, s, buf}
      end

    {s, %{state | client: %{state.client | count: c - 1, s: s, buf: buf}}}
  end

  def read_type_ref(%State{type_ref: %{count: count, s: s, buf: buf}} = state) do
    {c, s, buf} =
      if count == 0 do
        # Use read_int_with_sign to detect negative zero (RLE-encoded 0)
        {s, is_negative?, buf} = read_int_with_sign(buf)

        {c, buf} =
          if is_negative? do
            {c, buf} = read_uint(buf)
            {c + 2, buf}
          else
            {1, buf}
          end

        {c, s, buf}
      else
        {count, s, buf}
      end

    {s, %{state | type_ref: %{state.type_ref | count: c - 1, s: s, buf: buf}}}
  end

  def read_info(%State{info: %{count: count, s: s, buf: buf}} = state) do
    {c, s, buf} =
      if count == 0 do
        <<s::size(8), buf::binary>> = buf

        {c, buf} =
          if buf != <<>> do
            {c, buf} = read_uint(buf)
            {c + 1, buf}
          else
            {-1, buf}
          end

        {c, s, buf}
      else
        {count, s, buf}
      end

    {s, %{state | info: %{state.info | count: c - 1, s: s, buf: buf}}}
  end

  def read_len(%State{length: %{count: c, s: s, buf: buf}} = state) do
    {c, s, buf} =
      if c == 0 do
        # Use read_int_with_sign to detect negative zero (RLE-encoded 0)
        {s, is_negative?, buf} = read_int_with_sign(buf)

        if is_negative? do
          {c, buf} = read_uint(buf)
          {c + 2, s, buf}
        else
          {1, s, buf}
        end
      else
        {c, s, buf}
      end

    {s, %{state | length: %{state.length | count: c - 1, s: s, buf: buf}}}
  end

  def read_clock(which_clock?, state) when which_clock? in [:left, :right] do
    %{buf: buf, s: s, count: c, diff: diff} =
      case which_clock? do
        :left -> state.left_clock
        :right -> state.right_clock
      end

    {c, diff, buf} =
      if c == 0 do
        {diff, buf} = read_int(buf)
        has_count? = (diff &&& 1) != 0
        diff = floor(diff / 2)

        {c, buf} =
          if has_count? do
            {c, buf} = read_uint(buf)
            {c + 2, buf}
          else
            {1, buf}
          end

        {c, diff, buf}
      else
        {c, diff, buf}
      end

    s = s + diff

    if which_clock? == :left do
      {s, %{state | left_clock: %{state.left_clock | buf: buf, s: s, count: c - 1, diff: diff}}}
    else
      {s, %{state | right_clock: %{state.right_clock | buf: buf, s: s, count: c - 1, diff: diff}}}
    end
  end

  def read_parent_info(%State{parent_info: %{count: c, s: s, buf: buf}} = state) do
    {c, s, buf} =
      if c == 0 do
        {s, buf} = read_uint(buf)

        {c, buf} =
          if buf == <<>> do
            {-1, buf}
          else
            {c, buf} = read_uint(buf)
            {c + 1, buf}
          end

        {c, s, buf}
      else
        {c, s, buf}
      end

    {s, %{state | parent_info: %{state.parent_info | count: c - 1, s: s, buf: buf}}}
  end

  def read_string(%State{string: string, string_lengths: %{count: c, s: s, buf: buf}} = state) do
    {c, s, buf} =
      if c == 0 do
        # Use read_int_with_sign to detect negative zero (RLE-encoded 0)
        {s, is_negative?, buf} = read_int_with_sign(buf)

        if is_negative? do
          {c, buf} = read_uint(buf)
          {c + 2, s, buf}
        else
          {1, s, buf}
        end
      else
        {c, s, buf}
      end

    <<string_to_return::binary-size(^s), string_rest::binary>> = string

    {string_to_return,
     %{
       state
       | string_lengths: %{state.string_lengths | count: c - 1, s: s, buf: buf},
         string: string_rest
     }}
  end

  @doc """
  Read a key using the key clock decoder.
  If the key clock points to an existing key in the keys array, return it.
  Otherwise, read a new string and add it to the keys array.
  """
  def read_key(%State{key_clock: %{count: c, s: s, buf: buf}, keys: keys} = state) do
    # First, read the key clock value (similar to other RLE decoders)
    {c, s, buf} =
      if c == 0 do
        # Use read_int_with_sign to detect negative zero (RLE-encoded 0)
        {s, is_negative?, buf} = read_int_with_sign(buf)

        if is_negative? do
          {c, buf} = read_uint(buf)
          {c + 2, s, buf}
        else
          {1, s, buf}
        end
      else
        {c, s, buf}
      end

    key_clock_value = s
    state = %{state | key_clock: %{state.key_clock | count: c - 1, s: s, buf: buf}}

    # Check if this key clock points to an existing key
    if key_clock_value < length(keys) do
      # Return existing key
      key = Enum.at(keys, key_clock_value)
      {key, state}
    else
      # Read new key from string decoder and add to keys array
      {key, state} = read_string(state)
      {key, %{state | keys: keys ++ [key]}}
    end
  end
end
