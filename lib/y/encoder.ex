defmodule Y.Encoder do
  alias Y.Doc
  alias Y.ID
  alias Y.Item
  alias Y.GC
  alias Y.Skip
  alias Y.Type
  alias Y.Encoder.Buffer
  alias Y.Content.Binary
  alias Y.Content.Deleted

  import Y.Encoder.Buffer, only: [write: 3]
  import Y.Encoder.Operations
  import Bitwise

  def encode(doc_name) do
    with {:ok, doc} <- Doc.get_instance(doc_name),
         doc <- Doc.pack!(doc),
         sm <-
           doc
           |> Doc.highest_clock_with_length_by_client_id!()
           |> Enum.map(fn {k, _v} -> {k, 0} end)
           |> Enum.into(%{}) do
      Buffer.new()
      |> write_client_structs(doc, sm)
      |> write_delete_set(doc, sm)
      |> Buffer.dump()
    end
  end

  def encode_state_as_update(doc_name, encoded_target_state_vector) do
    with {:ok, doc} <- Doc.get_instance(doc_name),
         doc <- Doc.pack!(doc),
         target_sv <- Y.Decoder.decode_state_vector(encoded_target_state_vector) do
      current_sv = Doc.highest_clock_with_length_by_client_id!(doc)

      sm =
        current_sv
        |> Enum.filter(fn {client, clock} ->
          # Include if target doesn't have this client or target clock is lower
          target_clock = Map.get(target_sv, client, 0)
          clock > target_clock
        end)
        |> Enum.map(fn {client, _clock} ->
          # Start from target's clock for this client
          {client, Map.get(target_sv, client, 0)}
        end)
        |> Enum.into(%{})

      # Create delete set from structs (like Y.js createDeleteSetFromStructStore)
      delete_set = create_delete_set_from_structs(doc)

      update =
        Buffer.new()
        |> write_client_structs(doc, sm)
        |> write_id_set(delete_set)
        |> Buffer.dump()

      # Merge with pending structs/delete sets if any
      updates = [update]

      updates =
        case doc.pending_delete_sets do
          nil -> updates
          pending_ds -> updates ++ [encode_pending_delete_sets(pending_ds)]
        end

      updates =
        case doc.pending_structs do
          nil ->
            updates

          %{structs: structs} ->
            pending_update = encode_pending_structs(structs)
            diffed = diff_update(pending_update, encoded_target_state_vector)
            updates ++ [diffed]
        end

      case updates do
        [single] -> single
        multiple -> merge_updates(multiple)
      end
    end
  end

  # Placeholder for encoding pending delete sets
  # This creates an "update" that only contains delete set info, no structs
  defp encode_pending_delete_sets(pending_ds) do
    buffer =
      Buffer.new()
      # Write 0 clients (no structs)
      |> write(:rest, write_uint(0))
      # Write delete set
      |> write(:rest, write_uint(map_size(pending_ds)))

    pending_ds
    |> Enum.sort(fn {_, a}, {_, b} ->
      a_first = MapSet.to_list(a) |> hd() |> elem(0)
      b_first = MapSet.to_list(b) |> hd() |> elem(0)
      a_first >= b_first
    end)
    |> Enum.reduce(buffer, fn {client, delete_items}, buffer ->
      delete_items = MapSet.to_list(delete_items)

      buffer
      |> Buffer.reset_delete_set_current_value()
      |> write(:rest, write_uint(client))
      |> write(:rest, write_uint(length(delete_items)))
      |> then(fn buf ->
        Enum.reduce(delete_items, buf, fn {clock, length}, buf ->
          buf
          |> write(:ds_clock, clock)
          |> write(:ds_length, length)
        end)
      end)
    end)
    |> Buffer.dump()
  end

  # Placeholder for encoding pending structs
  defp encode_pending_structs(structs) do
    # Group structs by client
    by_client =
      structs
      |> Enum.group_by(fn item -> item.id.client end)
      |> Enum.map(fn {client, items} ->
        items = Enum.sort_by(items, & &1.id.clock)
        {client, items}
      end)
      |> Enum.into(%{})

    buffer =
      Buffer.new()
      |> write(:rest, write_uint(map_size(by_client)))

    buffer =
      by_client
      |> Enum.sort(:desc)
      |> Enum.reduce(buffer, fn {client, items}, buffer ->
        [first | _] = items
        start_clock = first.id.clock

        buffer
        |> write(:rest, write_uint(length(items)))
        |> write(:client, client)
        |> write(:rest, write_uint(start_clock))
        |> then(fn buf ->
          items
          |> Enum.reduce({buf, start_clock}, fn item, {buf, _clock} ->
            struct_end = item.id.clock + item.length
            {write_pending_struct(buf, item), struct_end}
          end)
          |> elem(0)
        end)
      end)

    # Write empty delete set
    buffer
    |> write(:rest, write_uint(0))
    |> Buffer.dump()
  end

  # Write a single pending struct (Item, GC, or Skip)
  defp write_pending_struct(buf, %Item{} = item) do
    # For pending items, we just write them as-is with offset 0
    # This is simplified - in production you'd want full item writing
    write_item(buf, item, nil, 0, 0)
  end

  defp write_pending_struct(buf, %GC{length: len}) do
    # GC has content ref 0
    buf
    |> write(:info, 0)
    |> write(:length, len)
  end

  defp write_pending_struct(buf, %Skip{length: len}) do
    # Skip has content ref 10
    buf
    |> write(:info, 10)
    |> write(:rest, write_uint(len))
  end

  # Diff update against target state vector
  # For now, this is a simplified version - returns update as-is
  # A full implementation would parse the update and filter out already-applied operations
  defp diff_update(update, _encoded_target_state_vector) do
    # TODO: Implement proper diffUpdateV2 logic
    # For now, return the update as-is since pending structs are already
    # items that failed to integrate
    update
  end

  # Merge multiple updates into one
  # For now, this is a simplified version
  defp merge_updates([single]), do: single

  defp merge_updates(updates) do
    # TODO: Implement proper mergeUpdatesV2 logic
    # For now, just return the first update
    # A full implementation would decode all updates, merge structs and delete sets,
    # and re-encode
    hd(updates)
  end

  def encode_state_vector(doc_name) do
    with {:ok, doc} <- Doc.get_instance(doc_name),
         doc <- Doc.pack!(doc),
         sv <- Doc.highest_clock_with_length_by_client_id!(doc) do
      Buffer.new()
      |> write(:rest, write_uint(map_size(sv)))
      |> then(fn buf ->
        sv
        # by client, desc
        |> Enum.sort_by(&elem(&1, 0), &>=/2)
        |> Enum.reduce(buf, fn {client, clock}, buf ->
          buf
          |> write(:rest, write_uint(client))
          |> write(:rest, write_uint(clock))
        end)
      end)
      |> Buffer.dump_rest_only!()
    end
  end

  defp write_client_structs(buffer, %Doc{} = doc, sm) do
    buffer
    |> write(:rest, write_uint(map_size(sm)))
    |> write_structs(sm, doc)
  end

  defp write_structs(buffer, %{} = sm, %Doc{} = doc) do
    sm = Enum.sort_by(sm, &elem(&1, 0), :desc)

    Enum.reduce(sm, buffer, fn {client, clock}, buffer ->
      case Doc.items_of_client!(doc, client) do
        [] ->
          buffer
          |> write(:rest, write_uint(0))
          |> write(:client, client)
          |> write(:rest, write_uint(clock))

        [%_{id: %ID{clock: f_clock}} | _] = items ->
          last_struct = List.last(items)
          id_range_len = last_struct.id.clock + last_struct.length - clock

          last_clock = last_struct.id.clock + last_struct.length

          start_clock = max(clock, f_clock)
          end_clock = min(clock + id_range_len, last_clock)

          structs_to_write =
            if start_clock >= end_clock do
              []
            else
              # Find structs that overlap with [start_clock, end_clock)
              # A struct overlaps if: struct.clock < end_clock AND struct.clock + struct.length > start_clock
              items
              |> Enum.filter(fn struct ->
                struct_start = struct.id.clock
                struct_end = struct.id.clock + struct.length
                struct_start < end_clock && struct_end > start_clock
              end)
            end

          buffer
          |> write(:rest, write_uint(length(structs_to_write)))
          |> write(:client, client)
          |> write(:rest, write_uint(clock))
          |> then(fn buf ->
            structs_to_write
            |> Enum.reduce({buf, clock}, fn item, {buf, clock} ->
              struct_end = item.id.clock + item.length
              offset_end = max(struct_end - end_clock, 0)

              {write_item(buf, item, doc, clock - item.id.clock, offset_end),
               struct_end - offset_end}
            end)
          end)
          |> elem(0)
      end
    end)
  end

  defp write_item(buf, %Item{id: id} = item, %Doc{} = doc, offset, offset_end) do
    # When offset > 0, we're encoding a partial item starting from an offset.
    # The origin should point to the previous element in the content.
    # This matches Y.JS: offset > 0 ? createID(this.id.client, this.id.clock + offset - 1) : this.origin
    origin =
      if offset > 0,
        do: ID.new(id.client, id.clock + offset - 1),
        else: item.origin

    origin_info = if origin == nil, do: 0, else: 128
    content_ref = Item.content_ref(item) &&& 31
    right_origin_info = if item.right_origin == nil, do: 0, else: 64
    parent_sub = if item.parent_sub == nil, do: 0, else: 32

    buf
    |> write(:info, content_ref ||| origin_info ||| right_origin_info ||| parent_sub)
    |> then(fn buf ->
      if origin, do: buf |> write(:left_id, origin), else: buf
    end)
    |> then(fn buf ->
      if item.right_origin, do: buf |> write(:right_id, item.right_origin), else: buf
    end)
    |> write_parent_info(origin, item, doc)
    |> write_content(item, offset, offset_end)
  end

  # Only write parent info if both origin and right_origin are nil
  # (using the calculated origin, not item.origin)
  defp write_parent_info(buf, nil = _origin, %Item{right_origin: nil} = item, %Doc{} = doc) do
    case Doc.get!(doc, item.parent_name) do
      {:ok, parent} ->
        # If the parent is a top-level type in doc.share (its name matches item.parent_name),
        # encode by name so receiving docs can find it in their doc.share.
        # Only use parent item ID for truly nested types that aren't in doc.share by name.
        parent_item = Doc.find_parent_item!(doc, item)

        use_parent_name =
          case parent do
            %ID{} -> false
            _ -> parent.name == item.parent_name
          end

        if use_parent_name do
          buf |> write(:parent_info, 1) |> write(:string, parent.name)
        else
          if parent_item do
            buf |> write(:parent_info, 0) |> write(:left_id, parent_item.id)
          else
            case parent do
              %ID{} ->
                buf |> write(:parent_info, 0) |> write(:left_id, parent)

              _ ->
                buf |> write(:parent_info, 1) |> write(:string, parent.name)
            end
          end
        end
        |> then(fn buf ->
          if item.parent_sub do
            buf |> write(:string, item.parent_sub)
          else
            buf
          end
        end)

      _ ->
        buf
    end
  end

  defp write_parent_info(buf, _origin, _item, _doc), do: buf

  defp write_content(buf, %Item{content: content} = item, offset, offset_end) do
    len = Item.content_length(item)
    end_ = len - offset_end

    buf
    |> write(:length, end_ - offset)
    |> then(fn buf ->
      content
      |> Enum.slice(offset..end_)
      |> Enum.reduce(buf, &write_any_content(&2, &1))
    end)
  end

  defp write_any_content(buf, c) do
    cond do
      is_bitstring(c) && String.valid?(c) ->
        buf |> write(:rest, <<119>>) |> write(:rest, write_string(c))

      is_bitstring(c) ->
        buf |> write(:rest, <<116>>) |> write(:rest, c)

      is_integer(c) && abs(c) <= 0x7FFFFFFF ->
        buf |> write(:rest, <<125>>) |> write(:rest, write_int(c))

      # bigint
      is_integer(c) ->
        buf |> write(:rest, <<122>>) |> write(:rest, write_bigint(c))

      # always float64
      is_float(c) ->
        buf |> write(:rest, <<124>>) |> write(:rest, write_float64(c))

      is_nil(c) ->
        buf |> write(:rest, <<126>>)

      is_list(c) ->
        buf = buf |> write(:rest, <<117>>) |> write(:rest, write_uint(length(c)))
        Enum.reduce(c, buf, &write_any_content(&2, &1))

      match?(%Binary{}, c) ->
        content = c.content
        buf |> write(:rest, <<byte_size(content), content::binary>>)

      match?(%Deleted{}, c) ->
        # length already written
        buf

      is_struct(c) && Type.impl_for(c) != nil ->
        buf |> write(:type_ref, Type.type_ref(c))

      is_struct(c) || is_map(c) ->
        c = if is_struct(c), do: Map.from_struct(c), else: c
        buf = buf |> write(:rest, <<118>>) |> write(:rest, write_uint(map_size(c)))

        Enum.reduce(c, buf, fn
          {k, v}, buf when is_atom(k) ->
            buf |> write(:rest, write_string(Atom.to_string(k))) |> write_any_content(v)

          {k, v}, buf ->
            buf |> write(:rest, write_string(k)) |> write_any_content(v)
        end)

      is_boolean(c) ->
        buf |> write(:rest, <<(c && 120) || 121>>)

      :otherwise ->
        buf |> write(:rest, <<127>>)
    end
  end

  # Iterates over all structs and finds deleted ones, merging consecutive
  # deleted structs into ranges.
  # Both deleted Items and GC structs are included (GC is always considered deleted).
  defp create_delete_set_from_structs(%Doc{} = doc) do
    doc.share
    |> Map.values()
    |> Enum.flat_map(fn type ->
      type
      |> Type.to_list(as_items: true, with_deleted: true)
    end)
    |> Enum.filter(&Item.deleted?/1)
    |> Enum.group_by(fn %_{id: %ID{client: client}} -> client end)
    |> Enum.map(fn {client, structs} ->
      # Sort structs by clock
      sorted_structs = Enum.sort_by(structs, fn %_{id: %ID{clock: clock}} -> clock end)

      # Merge consecutive deleted structs into ranges
      ranges =
        sorted_structs
        |> Enum.reduce([], fn struct, acc ->
          clock = struct.id.clock
          len = item_length(struct)

          case acc do
            [] ->
              [{clock, len}]

            [{last_clock, last_len} | rest] ->
              if last_clock + last_len == clock do
                # Consecutive - merge
                [{last_clock, last_len + len} | rest]
              else
                # Gap - start new range
                [{clock, len} | acc]
              end
          end
        end)
        |> Enum.reverse()

      {client, ranges}
    end)
    |> Enum.filter(fn {_client, ranges} -> ranges != [] end)
    |> Enum.into(%{})
  end

  defp item_length(%Item{} = item), do: Item.content_length(item)
  defp item_length(%GC{length: len}), do: len
  defp item_length(%Skip{length: len}), do: len

  # Write an IdSet (delete set) to the buffer
  # This follows the writeIdSet format from Y.js:
  # 1. Number of clients
  # 2. For each client (sorted descending by client id):
  #    - Reset ds cur val
  #    - Client id (VarUint)
  #    - Number of ranges (VarUint)
  #    - For each range: clock (delta encoded), len (minus 1)
  defp write_id_set(buffer, id_set) do
    buffer = buffer |> write(:rest, write_uint(map_size(id_set)))

    id_set
    # Sort by client id descending (as per Y.js writeIdSet)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.reduce(buffer, fn {client, ranges}, buffer ->
      buffer
      |> Buffer.reset_delete_set_current_value()
      |> write(:rest, write_uint(client))
      |> write(:rest, write_uint(length(ranges)))
      |> then(fn buf ->
        ranges
        |> Enum.reduce(buf, fn {clock, length}, buf ->
          buf
          |> write(:ds_clock, clock)
          |> write(:ds_length, length)
        end)
      end)
    end)
  end

  # Write the delete set from doc.delete_set (used by encode/1)
  # This follows the writeIdSet format from Y.js
  defp write_delete_set(buffer, doc, _target_sv) do
    ds = doc.delete_set

    # Prepare delete set entries sorted by clock within each client
    prepared_ds =
      ds
      |> Enum.map(fn {client, delete_items} ->
        items =
          delete_items
          |> MapSet.to_list()
          |> Enum.sort_by(&elem(&1, 0))

        {client, items}
      end)
      |> Enum.filter(fn {_client, items} -> items != [] end)
      |> Enum.into(%{})

    write_id_set(buffer, prepared_ds)
  end
end
