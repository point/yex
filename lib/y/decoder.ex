defmodule Y.Decoder do
  alias Y.Decoder.State
  alias Y.Item
  alias Y.ID
  alias Y.GC
  alias Y.Skip
  alias Y.Doc
  import Bitwise

  require Logger

  def decode(msg, transaction) do
    {_u, msg} = read_uint(msg)
    {key_clock, msg} = read_uint_array(msg)
    {client, msg} = read_uint_array(msg)
    {left_clock, msg} = read_uint_array(msg)
    {right_clock, msg} = read_uint_array(msg)
    {info, msg} = read_uint_array(msg)
    {string, msg} = read_uint_array(msg)
    {parent_info, msg} = read_uint_array(msg)
    {type_ref, msg} = read_uint_array(msg)
    {length, rest} = read_uint_array(msg)
    # {rest, <<>>} = read_uint_array(msg)

    decoder_state =
      State.new(
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
      )

    {decoder_state, transaction}
    |> read_client_structs()
    |> integrate_structs()
  end

  defp read_client_structs({state, transaction}) do
    {num_of_updates, state} = State.read_and_advance(state, :rest, &read_uint/1)

    1..num_of_updates
    |> Enum.reduce({state, transaction, %{}}, fn _, {state, transaction, client_refs} ->
      {num_of_structs, state} = State.read_and_advance(state, :rest, &read_uint/1)
      {client, state} = read_client(state)
      {clock, state} = State.read_and_advance(state, :rest, &read_uint/1)

      {state, transaction, structs, _clock} =
        1..num_of_structs
        |> Enum.reduce({state, transaction, [], clock}, fn _,
                                                           {state, transaction, structs, clock} ->
          read_struct(state, transaction, structs, client, clock)
        end)

      {state, transaction, Map.put_new(client_refs, client, Enum.reverse(structs))}
    end)
  end

  defp integrate_structs({_state, transaction, client_refs}) do
    client_refs
    |> Enum.sort(:desc)
    |> Enum.map(&elem(&1, 1))
    |> List.flatten()
    |> do_integrate([], transaction)
  end

  defp do_integrate([], [], transaction), do: transaction

  defp do_integrate([], items_to_retry, transaction) do
    # detect if there're duplicate elements in `items_to_retry`
    # duplication means we tried to `integrate` element at least twice,
    # so we exclude it from the retry list
    items_to_retry
    |> Enum.frequencies()
    |> Enum.reduce([], fn
      {item, 1}, acc -> [item | acc]
      {_item, _}, acc -> acc
    end)
    |> case do
      [] ->
        Logger.warning("Failed to integrate items. Tried > 1 times. Leaving unintegrated",
          items_to_retry: items_to_retry
        )

        transaction

      items_to_retry_with_retry_count_less_2 ->
        do_integrate(items_to_retry_with_retry_count_less_2, items_to_retry, transaction)
    end
  end

  defp do_integrate([item | rest_items], items_to_retry, transaction) do
    case integrate_item(item, transaction) do
      {:ok, new_transaction} ->
        do_integrate(rest_items, items_to_retry, new_transaction)

      {:retry, transaction} ->
        do_integrate(rest_items, [item | items_to_retry], transaction)

      err ->
        Logger.warning("Failed to integrate single item", item: item, error: err)
        do_integrate(rest_items, items_to_retry, transaction)
    end
  end

  def read_uint(msg) do
    {_num, _rest} = do_read_uint(msg, 0, 1)
  end

  def read_uint_array(<<s::size(8), msg::binary>>) when s == 0, do: {<<>>, msg}

  def read_uint_array(<<s::size(8), msg::binary>>) do
    <<a::binary-size(s), rest::binary>> = msg
    {a, rest}
  end

  def read_int(<<r::size(8), rest::binary>>) do
    num = r &&& 63
    mult = 64
    sign = if (r &&& 64) > 0, do: -1, else: 1

    if (r &&& 128) == 0 do
      {sign * num, rest}
    else
      {num, rest} = do_read_uint(rest, num, mult)
      {num * sign, rest}
    end
  end

  def read_string(<<r::size(8), rest::binary>>) do
    <<s::binary-size(^r), rest::binary>> = rest
    {s, rest}
  end

  # CASE 127: undefined
  def read_any(<<127, rest::binary>>), do: {nil, rest}
  # CASE 126: null
  def read_any(<<126, rest::binary>>), do: {nil, rest}
  # CASE 125: integer
  def read_any(<<125, rest::binary>>), do: read_int(rest)
  # CASE 124: float32
  def read_any(<<124, f::float-size(32), rest::binary>>), do: {f, rest}
  # CASE 123: float64
  def read_any(<<123, f::float, rest::binary>>), do: {f, rest}
  # CASE 122: bigint
  def read_any(<<122, i::integer-size(64), rest::binary>>), do: {i, rest}
  # CASE 121: boolean (false)
  def read_any(<<121, rest::binary>>), do: {false, rest}
  # CASE 120: boolean (true)
  def read_any(<<120, rest::binary>>), do: {true, rest}
  # CASE 119: string
  def read_any(<<119, rest::binary>>), do: read_string(rest)
  # CASE 118: map<string,any>
  def read_any(<<118, rest::binary>>) do
    {len, rest} = read_uint(rest)

    Enum.reduce(1..len, {%{}, rest}, fn _, {m, rest} ->
      {k, rest} = read_string(rest)
      {v, rest} = read_any(rest)
      {Map.put_new(m, k, v), rest}
    end)
  end

  # CASE 117: array<any>
  def read_any(<<117, rest::binary>>) do
    {len, rest} = read_uint(rest)

    {arr, rest} =
      Enum.reduce(1..len, {[], rest}, fn _, {arr, rest} ->
        {v, rest} = read_any(rest)
        {[v | arr], rest}
      end)

    {Enum.reverse(arr), rest}
  end

  # CASE 116: Uint8Array
  def read_any(<<116, rest::binary>>), do: read_uint_array(rest)

  defp do_read_uint(<<r::size(8), rest::binary>>, num, mult) do
    num = num + (r &&& 127) * mult
    if r < 128, do: {num, rest}, else: do_read_uint(rest, num, mult * 128)
  end

  defp read_client(%State{client: %{count: count, s: s, buf: buf}} = state) do
    {c, s, buf} =
      if count == 0 do
        {s, buf} = read_int(buf)
        c = 1
        {s, {c, buf}} = if s < 0, do: {-s, read_uint(buf)}, else: {s, {c, buf}}
        {c + 2, s, buf}
      else
        {count, s, buf}
      end

    {s, %{state | client: %{state.client | count: c - 1, s: s, buf: buf}}}
  end

  defp read_info(%State{info: %{count: count, s: s, buf: buf}} = state) do
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

  defp read_len(%State{length: %{count: c, s: s, buf: buf}} = state) do
    {c, s, buf} =
      if c == 0 do
        {s, buf} = read_int(buf)

        if s < 0 do
          {c, buf} = read_uint(buf)
          {c + 2, -s, buf}
        else
          {c, s, buf}
        end
      else
        {c, s, buf}
      end

    {s, %{state | length: %{state.length | count: c - 1, s: s, buf: buf}}}
  end

  defp read_clock(which_clock?, state) when which_clock? in [:left, :right] do
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
        c = 1

        {c, buf} =
          if has_count? do
            {c, buf} = read_uint(buf)
            {c + 2, buf}
          else
            {c, buf}
          end

        {c, diff, buf}
      else
        {c, diff, buf}
      end

    s = s + diff

    if which_clock? == :left do
      {s, %{state | left_clock: %{state.left_clock | buf: buf, s: s, count: c, diff: diff}}}
    else
      {s, %{state | right_clock: %{state.right_clock | buf: buf, s: s, count: c, diff: diff}}}
    end
  end

  defp read_parent_info(%State{parent_info: %{count: c, s: s, buf: buf}} = state) do
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

  defp read_content(0, _), do: raise("GC is not ItemContent")

  # read deleted content
  defp read_content(1, state) do
    {len, state} = State.read_and_advance(state, :rest, &read_uint/1)
    {Y.Content.Deleted.new(len), state}
  end

  # read json content
  defp read_content(2, state) do
    {len, state} = State.read_and_advance(state, :rest, &read_uint/1)

    {cs, state} =
      Enum.reduce(1..len, {[], state}, fn _, {cs, state} ->
        {c, state} = State.read_and_advance(state, :rest, &read_string/1)

        case c do
          "undefined" ->
            {[nil | cs], state}

          str ->
            e = Jason.decode!(str)
            {[e | cs], state}
        end
      end)

    cs = Enum.reverse(cs)
    {Y.Content.JSON.new(cs), state}
  end

  # read binary content
  defp read_content(3, state) do
    {arr, state} = State.read_and_advance(state, :rest, &read_uint_array/1)
    {[Y.Content.Binary.new(arr)], state}
  end

  # read binary string
  defp read_content(4, state), do: State.read_and_advance(state, :rest, &read_string/1)

  # read content embed
  defp read_content(5, _state) do
    raise "Don't know how to read content embed"
  end

  # read content format
  defp read_content(6, _state) do
    raise "Don't know how to read content format"
  end

  # read content type
  defp read_content(7, _state) do
    raise "Don't know how to read content type"
  end

  # read content any
  defp read_content(8, state) do
    {len, state} = read_len(state)

    {cs, state} =
      Enum.reduce(1..len, {[], state}, fn _, {cs, state} ->
        {c, state} = State.read_and_advance(state, :rest, &read_any/1)
        {[c | cs], state}
      end)

    {Enum.reverse(cs), state}
  end

  # read content type
  defp read_content(9, _state) do
    raise "Don't know how to read content doc"
  end

  defp read_struct(state, transaction, structs, client, clock) do
    {info, state} = read_info(state)

    case info &&& 31 do
      # GC
      0 ->
        {len, state} = read_len(state)
        gc = GC.new(ID.new(client, clock), len)
        {state, transaction, [gc | structs], clock + len}

      # Skip Struct
      10 ->
        {len, state} = State.read_and_advance(state, :rest, &read_uint/1)
        skip = Skip.new(ID.new(client, clock), len)
        {state, transaction, [skip | structs], clock + len}

      # Item with content
      _ ->
        {item, state, transaction} = read_item(state, transaction, client, clock, info)
        {state, transaction, [item | structs], clock + Item.content_length(item)}
    end
  end

  defp read_item(state, transaction, client, clock, info) do
    cant_copy_parent_info? = (info &&& (64 ||| 128)) == 0

    {origin, state} =
      if (info &&& 128) == 128 do
        {client, state} = read_client(state)
        {clock, state} = read_clock(:left, state)
        {ID.new(client, clock), state}
      else
        {nil, state}
      end

    {right_origin, state} =
      if (info &&& 64) == 64 do
        {client, state} = read_client(state)
        {clock, state} = read_clock(:right, state)
        {ID.new(client, clock), state}
      else
        {nil, state}
      end

    {parent, state, transaction} =
      if cant_copy_parent_info? do
        {parent_info, state} = read_parent_info(state)

        if parent_info == 1 do
          {parent_name, state} = State.read_and_advance(state, :string, &read_string/1)
          {parent_name, state, transaction}
        else
          # {client, state} = State.read_and_advance(state, :rest, &read_uint/1)
          # {clock, state} = State.read_and_advance(state, :rest, &read_uint/1)
          {client, state} = read_client(state)
          {clock, state} = read_clock(:left, state)
          {ID.new(client, clock), state, transaction}
        end
      else
        {nil, state, transaction}
      end

    {parent_sub, state} =
      if cant_copy_parent_info? && (info &&& 32) == 32 do
        State.read_and_advance(state, :string, &read_string/1)
      else
        {nil, state}
      end

    {content, state} = read_content(info &&& 31, state)

    item =
      Item.new(
        id: ID.new(client, clock),
        origin: origin,
        right_origin: right_origin,
        parent_name: parent,
        parent_sub: parent_sub,
        content: content
      )

    {item, state, transaction}
  end

  defp integrate_item(%Skip{}, transaction), do: {:ok, transaction}

  defp integrate_item(%Item{} = item, transaction) do
    local_clock = Doc.highest_clock_with_length(transaction, item.id.client)
    offset = local_clock - item.id.clock

    cond do
      # update from the same client is missing
      offset < 0 ->
        {:retry, transaction}

      offset == 0 || offset < Item.content_length(item) ->
        Item.integrate(item, transaction, offset)

      :otherwise ->
        {:skip, transaction}
    end
  end
end
