defmodule Y.Encoder do
  alias Y.Doc
  alias Y.ID
  alias Y.Item
  alias Y.Type
  alias Y.Encoder.Buffer
  alias Y.Content.Binary

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

  defp write_client_structs(buffer, %Doc{} = doc, sm) do
    buffer
    |> write(:rest, write_uint(map_size(sm)))
    |> write_structs(sm, doc)
  end

  defp write_structs(buffer, %{} = sm, %Doc{} = doc, opts \\ []) do
    sort = Keyword.get(opts, :sort)

    sm =
      cond do
        sort in [:asc, :desc] -> Enum.sort(sm, sort)
        :otherwise -> Map.to_list(sm)
      end

    Enum.reduce(sm, buffer, fn {client, clock}, buffer ->
      case Doc.items_of_client!(doc, client) do
        [] ->
          buffer
          |> write(:rest, write_uint(0))
          |> write(:client, client)
          |> write(:rest, write_uint(clock))

        [%_{id: %ID{clock: f_clock}} | _] = items ->
          clock = max(clock, f_clock)

          buffer
          |> write(:rest, write_uint(length(items)))
          |> write(:client, client)
          |> write(:rest, write_uint(clock))
          |> then(fn buf ->
            items
            |> Enum.with_index()
            |> Enum.reduce(buf, fn
              {item, 0}, buf -> write_item(buf, item, doc, clock - f_clock)
              {item, _}, buf -> write_item(buf, item, doc)
            end)
          end)
      end
    end)
  end

  defp write_item(buf, %Item{id: id} = item, %Doc{} = doc, offset \\ 0) do
    origin =
      if offset > 0 && item.origin,
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
    |> write_parent_info(item, doc)
    |> write_content(item, offset)
  end

  defp write_parent_info(buf, %Item{origin: nil, right_origin: nil} = item, %Doc{} = doc) do
    case Doc.get!(doc, item.parent_name) do
      {:ok, parent} ->
        if parent_item = Doc.find_parent_item!(doc, item) do
          buf |> write(:parent_info, 0) |> write(:left_id, parent_item.id)
        else
          case parent do
            %ID{} ->
              buf |> write(:parent_info, 0) |> write(:left_id, parent)

            _ ->
              buf |> write(:parent_info, 1) |> write(:string, parent.name)
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

  defp write_parent_info(buf, _, _), do: buf

  defp write_content(buf, %Item{content: content}, offset) do
    len = length(content)

    buf
    |> write(:length, len - offset)
    |> then(fn buf ->
      content
      |> Enum.slice(offset..-1//1)
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

  defp write_delete_set(buffer, doc, _sm) do
    ds = doc.delete_set
    buffer = buffer |> write(:rest, write_uint(map_size(ds)))

    ds
    |> Enum.sort(fn {_, a}, {_, b} -> MapSet.to_list(a) |> hd() >= MapSet.to_list(b) |> hd() end)
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
  end
end
