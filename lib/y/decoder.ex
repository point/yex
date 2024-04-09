defmodule Y.Decoder do
  alias Y.Decoder.State
  alias Y.Item
  alias Y.ID
  alias Y.GC
  alias Y.Skip
  alias Y.Doc
  alias Y.Type
  alias Y.Transaction
  import Bitwise

  require Logger

  defmodule InternalState do
    defstruct [
      :decoder_state,
      :transaction,
      :client_refs,
      :retry?,
      :retry_count,
      :failed_to_integrate,
      :missing_sv,
      :unapplied_delete_sets
    ]
  end

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
      Y.Decoder.State.new(
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
        delete_set_cur_val: 0
      )

    %InternalState{
      decoder_state: decoder_state,
      transaction: transaction,
      client_refs: %{},
      retry?: false,
      retry_count: 0,
      failed_to_integrate: [],
      missing_sv: %{},
      unapplied_delete_sets: %{}
    }
    |> read_client_structs()
    |> integrate_structs()
    |> merge_failed_to_integrate_structs()
    |> read_and_apply_delete_set()
    |> merge_failed_delete_sets()
    |> finalize_or_retry()
  end

  defp finalize_or_retry(%{retry?: true, retry_count: retry_count} = internal_state)
       when retry_count < 5 do
    transaction = internal_state.transaction
    doc = transaction.doc
    pending_structs = doc.pending_structs.structs

    %{
      internal_state
      | transaction: %Transaction{transaction | doc: %{doc | pending_structs: nil}},
        decoder_state: nil,
        client_refs: %{},
        failed_to_integrate: [],
        missing_sv: %{},
        unapplied_delete_sets: %{},
        retry_count: internal_state.retry_count + 1
    }
    |> integrate_structs(pending_structs)
    |> merge_failed_to_integrate_structs()
    |> read_and_apply_delete_set()
    |> merge_failed_delete_sets()
    |> finalize_or_retry()
  end

  defp finalize_or_retry(%{transaction: transaction}), do: transaction

  defp read_client_structs(internal_state) do
    {num_of_updates, state} =
      State.read_and_advance(internal_state.decoder_state, :rest, &read_uint/1)

    internal_state = %{internal_state | decoder_state: state}

    1..num_of_updates//1
    |> Enum.reduce(internal_state, fn _,
                                      %{
                                        decoder_state: state,
                                        transaction: transaction,
                                        client_refs: client_refs
                                      } = s ->
      {num_of_structs, state} = State.read_and_advance(state, :rest, &read_uint/1)
      {client, state} = read_client(state)
      {clock, state} = State.read_and_advance(state, :rest, &read_uint/1)

      {state, transaction, structs, _clock} =
        1..num_of_structs//1
        |> Enum.reduce({state, transaction, [], clock}, fn _,
                                                           {state, transaction, structs, clock} ->
          read_struct(state, transaction, structs, client, clock)
        end)

      %{
        s
        | decoder_state: state,
          transaction: transaction,
          client_refs: Map.put_new(client_refs, client, Enum.reverse(structs))
      }
    end)
  end

  defp integrate_structs(internal_state, structs) do
    structs
    |> Enum.sort_by(& &1.id.client, :desc)
    |> do_integrate([], internal_state)
  end

  defp integrate_structs(%{client_refs: client_refs} = internal_state) do
    client_refs
    |> Enum.sort(:desc)
    |> Enum.map(&elem(&1, 1))
    |> List.flatten()
    |> do_integrate([], internal_state)
  end

  defp do_integrate([], [], internal_state), do: internal_state

  defp do_integrate(
         [],
         items_to_retry,
         %{transaction: transaction, failed_to_integrate: failed_to_integrate} = internal_state
       ) do
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

        %{
          internal_state
          | transaction: transaction,
            failed_to_integrate: failed_to_integrate ++ items_to_retry
        }

      items_to_retry_with_retry_count_less_2 ->
        do_integrate(items_to_retry_with_retry_count_less_2, items_to_retry, transaction)
    end
  end

  defp do_integrate(
         [item | rest_items],
         items_to_retry,
         %{transaction: transaction} = internal_state
       ) do
    case integrate_item(item, transaction) do
      {:ok, new_transaction} ->
        do_integrate(rest_items, items_to_retry, %{internal_state | transaction: new_transaction})

      {:retry, new_transaction} ->
        do_integrate(rest_items, [item | items_to_retry], %{
          internal_state
          | transaction: new_transaction,
            missing_sv:
              Map.update(
                internal_state.missing_sv,
                item.id.client,
                item.id.clock - 1,
                fn existing ->
                  if existing > item.id.clock, do: item.id.clock, else: existing
                end
              )
        })

      {:invalid, new_transaction} ->
        client =
          case item do
            %{origin: %{client: client}} -> client
            %{right_origin: %{client: client}} -> client
            %{parent_name: %{client: client}} -> client
          end

        clock = Doc.highest_clock_with_length(new_transaction, client)

        do_integrate(rest_items, [item | items_to_retry], %{
          internal_state
          | transaction: new_transaction,
            missing_sv:
              Map.update(
                internal_state.missing_sv,
                client,
                clock,
                fn existing ->
                  if existing > clock, do: clock, else: existing
                end
              )
        })

      err ->
        Logger.warning("Failed to integrate single item", item: item, error: err)
        do_integrate(rest_items, items_to_retry, internal_state)
    end
  end

  defp read_uint(msg) do
    {_num, _rest} = do_read_uint(msg, 0, 1)
  end

  defp read_uint_array(<<s::size(8), msg::binary>>) when s == 0, do: {<<>>, msg}

  defp read_uint_array(<<s::size(8), msg::binary>>) do
    <<a::binary-size(s), rest::binary>> = msg
    {a, rest}
  end

  defp read_int(<<r::size(8), rest::binary>>) do
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

  defp read_string(<<r::size(8), rest::binary>>) do
    <<s::binary-size(^r), rest::binary>> = rest
    {s, rest}
  end

  # CASE 127: undefined
  defp read_any(<<127, rest::binary>>), do: {nil, rest}
  # CASE 126: null
  defp read_any(<<126, rest::binary>>), do: {nil, rest}
  # CASE 125: integer
  defp read_any(<<125, rest::binary>>), do: read_int(rest)
  # CASE 124: float32
  defp read_any(<<124, f::float-size(32), rest::binary>>), do: {f, rest}
  # CASE 123: float64
  defp read_any(<<123, f::float, rest::binary>>), do: {f, rest}
  # CASE 122: bigint
  defp read_any(<<122, i::integer-size(64), rest::binary>>), do: {i, rest}
  # CASE 121: boolean (false)
  defp read_any(<<121, rest::binary>>), do: {false, rest}
  # CASE 120: boolean (true)
  defp read_any(<<120, rest::binary>>), do: {true, rest}
  # CASE 119: string
  defp read_any(<<119, rest::binary>>), do: read_string(rest)
  # CASE 118: map<string,any>
  defp read_any(<<118, rest::binary>>) do
    {len, rest} = read_uint(rest)

    Enum.reduce(1..len//1, {%{}, rest}, fn _, {m, rest} ->
      {k, rest} = read_string(rest)
      {v, rest} = read_any(rest)
      {Map.put_new(m, k, v), rest}
    end)
  end

  # CASE 117: array<any>
  defp read_any(<<117, rest::binary>>) do
    {len, rest} = read_uint(rest)

    {arr, rest} =
      Enum.reduce(1..len//1, {[], rest}, fn _, {arr, rest} ->
        {v, rest} = read_any(rest)
        {[v | arr], rest}
      end)

    {Enum.reverse(arr), rest}
  end

  # CASE 116: Uint8Array
  defp read_any(<<116, rest::binary>>), do: read_uint_array(rest)

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
      Enum.reduce(1..len//1, {[], state}, fn _, {cs, state} ->
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
      Enum.reduce(1..len//1, {[], state}, fn _, {cs, state} ->
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

  defp merge_failed_to_integrate_structs(%{failed_to_integrate: []} = internal_state) do
    internal_state
  end

  defp merge_failed_to_integrate_structs(
         %{transaction: %Transaction{doc: %{pending_structs: nil}} = transaction} = internal_state
       ) do
    %{
      internal_state
      | transaction:
          Doc.put_pending_structs(transaction, %{
            structs: internal_state.failed_to_integrate,
            missing_sv: internal_state.missing_sv
          })
    }
  end

  defp merge_failed_to_integrate_structs(
         %{
           transaction: transaction,
           retry?: retry?,
           failed_to_integrate: failed_to_integrate,
           missing_sv: missing_sv
         } = internal_state
       ) do
    current_missing = transaction.doc.pending_structs[:missing_sv]

    retry? =
      retry? ||
        Enum.reduce_while(current_missing, retry?, fn {client, clock}, retry? ->
          if clock < Doc.highest_clock_with_length(transaction, client) do
            {:halt, true}
          else
            {:cont, retry?}
          end
        end)

    new_missing =
      Enum.reduce(missing_sv, current_missing, fn {client, clock}, missing ->
        mclock = Map.get(missing, client)

        if mclock == nil || mclock > clock do
          Map.put(missing, client, clock)
        else
          missing
        end
      end)

    new_structs =
      merge_structs(
        transaction.doc.pending_structs.structs,
        failed_to_integrate
      )

    %{
      internal_state
      | transaction:
          Doc.put_pending_structs(internal_state.transaction, %{
            structs: new_structs,
            missing_sv: new_missing
          }),
        retry?: retry?
    }
  end

  defp merge_structs(doc_structs, pending_structs) do
    do_merge_structs(doc_structs, pending_structs, nil, []) |> Enum.reverse()
  end

  defp do_merge_structs([], [], nil, acc), do: acc
  defp do_merge_structs([], [], current_item, acc), do: [current_item | acc]

  defp do_merge_structs(list1, list2, nil = _current_item, acc) do
    {[f | rest], list2} = select_struct(list1, list2)
    do_merge_structs(rest, list2, f, acc)
  end

  defp do_merge_structs(list1, list2, current_item, acc) do
    {[f | _] = list_to_iterate_over, new_list2} = select_struct(list1, list2)

    case find_and_ff(list_to_iterate_over, current_item) do
      [new_f | _] = list ->
        if new_f.id.client != f.id.client ||
             (f != new_f && new_f.id.clock > current_item.id.clock + current_item.id.length) do
          do_merge_structs(list, new_list2, current_item, acc)
        else
          {list, current_item, acc} =
            append_to_acc(f.id.client, current_item, list, acc)

          {list, current_item, acc} =
            finalize_acc(f.id.client, current_item, list, acc)

          do_merge_structs(list, new_list2, current_item, acc)
        end

      [] ->
        do_merge_structs([], new_list2, current_item, acc)
    end
  end

  defp append_to_acc(first_client, current_item, [new_f | rest], acc)
       when first_client != current_item.id.client do
    {rest, new_f, [current_item | acc]}
  end

  # extend existing skip
  defp append_to_acc(first_client, %Skip{} = current_item, [new_f | _] = list, acc)
       when first_client == current_item.id.client and
              current_item.id.clock + current_item.length < new_f.id.clock do
    {
      list,
      %{
        current_item
        | length: new_f.id.clock + new_f.length - current_item.id.clock
      },
      acc
    }
  end

  defp append_to_acc(first_client, current_item, [new_f | _] = list, acc)
       when first_client == current_item.id.client and
              current_item.id.clock + current_item.length < new_f.id.clock do
    diff = new_f.id.clock - current_item.id.clock - current_item.length

    {
      list,
      Skip.new(ID.new(first_client, current_item.id.clock + current_item.length), diff),
      acc
    }
  end

  # prefer to slice Skip because the other struct might contain more information
  defp append_to_acc(first_client, current_item, [new_f | rest] = list, acc)
       when first_client == current_item.id.client do
    diff = current_item.id.clock + current_item.length - new_f.id.clock

    {current_item, new_f} =
      cond do
        diff > 0 && match?(%Skip{}, current_item) ->
          {%{current_item | length: current_item.length - diff}, new_f}

        diff > 0 ->
          {current_item, slice_item(new_f, diff)}

        :otherwise ->
          {current_item, new_f}
      end

    if Item.mergeable?(current_item, new_f) do
      {
        list,
        Item.merge!(current_item, new_f),
        acc
      }
    else
      {
        rest,
        new_f,
        [current_item | acc]
      }
    end
  end

  defp finalize_acc(_first_client, current_item, [], acc),
    do: {[], current_item, acc}

  defp finalize_acc(first_client, current_item, [next | rest] = list, acc) do
    if next.id.client == first_client &&
         next.id.clock == current_item.id.clock + current_item.length && !match?(%Skip{}, next) do
      finalize_acc(first_client, next, rest, [current_item | acc])
    else
      {list, current_item, acc}
    end
  end

  defp slice_item(%GC{} = item, diff) do
    GC.new(ID.new(item.id.client, item.id.clock + diff), item.length - diff)
  end

  defp slice_item(%Skip{} = item, diff) do
    Skip.new(ID.new(item.id.client, item.id.clock + diff), item.length - diff)
  end

  defp slice_item(%Item{} = item, diff) do
    Item.new(
      id: ID.new(item.id.client, item.id.clock + diff),
      origin: ID.new(item.id.client, item.id.clock + diff - 1),
      right_origin: item.right_origin,
      parent_name: item.parent_name,
      parent_sub: item.parent_sub,
      content: Enum.slice(item.content, 1..-1//1)
    )
  end

  defp select_struct([], list2), do: {list2, []}
  defp select_struct(list1, []), do: {list1, []}

  defp select_struct(list1, list2) do
    [d1 | _] = list1
    [p1 | _] = list2

    cond do
      d1.id.client == p1.id.client == 0 ->
        cond do
          d1.id.clock - p1.id.clock == 0 && d1.__struct__ == p1.__struct__ -> {list1, list2}
          d1.id.clock - p1.id.clock == 0 && match?(%Skip{}, d1) -> {list2, list1}
          d1.id.clock - p1.id.clock == 0 -> {list1, list2}
          d1.id.clock - p1.id.clock < 0 -> {list2, list1}
          d1.id.clock - p1.id.clock > 0 -> {list2, list1}
        end

      p1.id.client > d1.id.client ->
        {list1, list2}

      p1.id.client < d1.id.client ->
        {list2, list1}
    end
  end

  defp find_and_ff([], _current_item), do: []

  defp find_and_ff([%Skip{} | rest], current_item), do: find_and_ff(rest, current_item)

  defp find_and_ff([f | rest] = list, current_item) do
    if f.id.clock + f.length <= current_item.id.clock + current_item.length &&
         f.id.client >= current_item.id.client do
      find_and_ff(rest, current_item)
    else
      list
    end
  end

  defp read_and_apply_delete_set(
         %{decoder_state: state, transaction: transaction} = internal_state
       ) do
    {num_clients, state} = State.read_and_advance(state, :rest, &read_uint/1)

    {transaction, state, unapplied_delete_sets} =
      Enum.reduce(1..num_clients//1, {transaction, state, %{}}, fn _,
                                                                   {transaction, state,
                                                                    unapplied_delete_sets} ->
        {client, state} =
          state
          |> State.reset_ds_cur_val()
          |> State.read_and_advance(:rest, &read_uint/1)

        {num_of_deletes, state} = State.read_and_advance(state, :rest, &read_uint/1)

        highest_clock = Doc.highest_clock_with_length(transaction, client)

        Enum.reduce(1..num_of_deletes//1, {transaction, state, unapplied_delete_sets}, fn _,
                                                                                          {transaction,
                                                                                           state,
                                                                                           unapplied_delete_sets} ->
          {clock, state} = State.read_ds_clock(state, &read_uint/1)
          {len, state} = State.read_ds_len(state, &read_uint/1)
          clock_end = clock + len

          {transaction, unapplied_delete_sets} =
            if clock < highest_clock do
              {_transaction, _unapplied_delete_sets} =
                find_and_mark_as_deleted(
                  transaction,
                  highest_clock,
                  client,
                  clock,
                  clock_end,
                  unapplied_delete_sets
                )
            else
              unapplied_delete_sets =
                Map.update(
                  unapplied_delete_sets,
                  client,
                  MapSet.new([{clock, clock_end - clock}]),
                  &MapSet.put(&1, {clock, clock_end - clock})
                )

              {transaction, unapplied_delete_sets}
            end

          {transaction, state, unapplied_delete_sets}
        end)
      end)

    %{
      internal_state
      | transaction: transaction,
        decoder_state: state,
        unapplied_delete_sets: unapplied_delete_sets
    }
  end

  defp find_and_mark_as_deleted(
         transaction,
         highest_clock,
         client,
         clock,
         clock_end,
         unapplied_delete_sets
       ) do
    unapplied_delete_sets =
      if highest_clock < clock_end do
        Map.update(
          unapplied_delete_sets,
          client,
          MapSet.new([{clock, clock_end - clock}]),
          &MapSet.put(&1, {clock, clock_end - clock})
        )
      else
        unapplied_delete_sets
      end

    case Doc.type_with_id!(transaction.doc, ID.new(client, clock)) do
      nil ->
        {transaction, unapplied_delete_sets}

      type ->
        transaction = do_mark_as_deleted(transaction, type, client, clock, clock_end)
        {transaction, unapplied_delete_sets}
    end
  end

  defp do_mark_as_deleted(transaction, _type, _client, clock, clock_end) when clock >= clock_end,
    do: transaction

  defp do_mark_as_deleted(transaction, type, client, clock, clock_end) do
    case Type.delete(type, transaction, ID.new(client, clock)) do
      {:ok, transaction} -> do_mark_as_deleted(transaction, type, client, clock + 1, clock_end)
      _ -> transaction
    end
  end

  defp merge_failed_delete_sets(%{unapplied_delete_sets: u} = internal_state)
       when map_size(u) == 0,
       do: internal_state

  defp merge_failed_delete_sets(
         %{
           transaction: %Transaction{doc: %{pending_delete_sets: nil}} = transaction,
           unapplied_delete_sets: u
         } = internal_state
       ) do
    %{internal_state | transaction: Doc.put_pending_delete_sets(transaction, u)}
  end

  defp merge_failed_delete_sets(
         %{
           transaction: transaction,
           unapplied_delete_sets: u
         } = internal_state
       ) do
    %{
      internal_state
      | transaction:
          Doc.put_pending_delete_sets(
            transaction,
            merge_structs(
              transaction.doc.pending_delete_sets,
              u
            )
          )
    }
  end
end
