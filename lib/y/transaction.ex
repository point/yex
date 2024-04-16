defmodule Y.Transaction do
  alias __MODULE__
  alias Y.Doc
  alias Y.Item
  alias Y.Type

  defstruct doc: nil,
            doc_before: nil,
            delete_set: %{},
            before_state: nil,
            after_state: %{},
            changed: MapSet.new(),
            changed_parent_types: %{},
            merge_structs: [],
            origin: nil,
            meta: %{},
            local: false,
            subdocs_added: MapSet.new(),
            subdocs_removed: MapSet.new(),
            subdocs_loaded: MapSet.new(),
            need_formatting_cleanup: false,
            need_pack: false

  def new(%Doc{} = doc, origin, local) do
    t = %Transaction{
      doc: doc,
      doc_before: doc,
      origin: origin,
      local: local
    }

    %{t | before_state: Doc.highest_clock_with_length(t, :all)}
  end

  def update(transaction, type) do
    {:ok,
     %{
       transaction
       | doc: Doc.replace(transaction.doc, type),
         changed: MapSet.put(transaction.changed, type.name)
     }}
  end

  def finalize(%Transaction{doc: doc, doc_before: doc_before, changed: changed} = transaction) do
    changed_names = MapSet.to_list(changed)

    delete_set =
      Enum.reduce(doc.share, transaction.delete_set, fn {type_name, type}, delete_set ->
        with true <- type_name in changed_names,
             {:ok, type_before} <- Doc.get!(doc_before, type_name) do
          put_deleted_to_delete_set(delete_set, type, type_before)
        else
          _ -> delete_set
        end
      end)

    %{transaction | delete_set: delete_set}
    |> merge_delete_sets_to_doc()
  end

  def force_pack(%Transaction{} = transaction), do: %{transaction | need_pack: true}

  def cleanup(%Transaction{need_pack: true} = transaction), do: Doc.pack(transaction)
  def cleanup(transaction), do: transaction

  def add_to_delete_set(transaction, client, clock, length \\ 1) do
    ds =
      Map.update(
        transaction.delete_set,
        client,
        MapSet.new([{clock, length}]),
        &MapSet.put(&1, {clock, length})
      )

    %{transaction | delete_set: ds}
  end

  defp put_deleted_to_delete_set(delete_set, type, type_before) do
    Enum.reduce(Type.to_list(type, as_items: true, with_deleted: true), delete_set, fn
      %Item{deleted?: true} = item, ds ->
        case Type.find(type_before, item.id) do
          %Item{deleted?: false} ->
            Map.update(
              ds,
              item.id.client,
              MapSet.new([{item.id.clock, item.length}]),
              &MapSet.put(&1, {item.id.clock, item.length})
            )

          _ ->
            ds
        end

      _, ds ->
        ds
    end)
  end

  defp merge_delete_sets_to_doc(
         %Transaction{doc: %{delete_set: doc_delete_set} = doc, delete_set: delete_set} =
           transaction
       ) do
    ds =
      Map.merge(doc_delete_set, delete_set, fn _k, v1, v2 ->
        MapSet.union(v1, v2)
      end)

    %{transaction | doc: %{doc | delete_set: ds}}
  end

  # def cleanup(%Doc{} = doc, []), do: doc
  #
  # def cleanup(%Doc{} = doc, [transaction | rest_transactions_to_cleanup]) do
  #   store = doc.store
  #   merge_structs = transaction.merge_structs
  #
  #   transaction
  #   |> struct(delete_set: DeleteSet.sort_and_merge_delete_set(transaction.delete_set))
  #   |> struct(after_state: Store.state_vector(doc.store))
  #   |> then(fn
  #     %{need_formatting_cleanup: true} = transaction ->
  #       Text.cleanup_text_after_transaction(transaction)
  #
  #     t ->
  #       t
  #   end)
  #   |> try_gc_delete_set(doc)
  #   |> then(fn {transaction, doc} ->
  #     try_merge_delete_set(transaction, doc)
  #   end)
  #   |> then(fn {%{after_state: after_state, before_state: before_state} = transaction,
  #               %{store: %Store{clients: clients}} = doc} ->
  #     new_s_clients =
  #       after_state
  #       |> Enum.map(fn {client, clock} ->
  #         before_clock = Map.get(before_state, client, 0)
  #         structs = Map.get(clients, client, [])
  #
  #         new_structs =
  #           if before_clock != clock do
  #             structs
  #             |> Enum.chunk_by(fn s -> s.clock <= before_clock end)
  #             |> then(fn [left, right] ->
  #               left ++ merge_with_lefts(doc, right)
  #             end)
  #           else
  #             structs
  #           end
  #
  #         {client, new_structs}
  #       end)
  #       |> Enum.into(%{})
  #
  #     d = %{doc | store: %{store | clients: new_s_clients}}
  #     {transaction, d}
  #   end)
  #   |> then(fn {%{merge_structs: merge_structs} = transaction,
  #               %{store: %Store{clients: clients}} = doc} ->
  #     new_s_clients =
  #       for %{id: %ID{clock: clock, client: client}} <- merge_structs, into: %{} do
  #         new_structs =
  #           clients
  #           |> Map.get(client, [])
  #           |> Enum.chunk_by(fn s -> s.clock <= clock end)
  #           |> then(fn [left, right] ->
  #             left ++
  #               case right do
  #                 [] ->
  #                   []
  #
  #                 [first_right | rest_right] ->
  #                   new_rest_right = merge_with_lefts(doc, rest_right)
  #
  #                   if length(new_rest_right) != rest_right,
  #                     do: new_rest_right,
  #                     else: merge_with_lefts(doc, right)
  #               end
  #           end)
  #
  #         {client, new_structs}
  #       end
  #
  #     d = %{doc | store: %{store | clients: new_s_clients}}
  #     {transaction, d}
  #   end)
  #   |> then(fn {%{after_state: after_state, before_state: before_state} = transaction,
  #               %{client_id: client_id} = doc} ->
  #     if !transaction.local &&
  #          Map.get(after_state, client_id) !== Map.get(before_state, client_id) do
  #       {transaction, %{doc | client_id: System.unique_integer()}}
  #     else
  #       {transaction, doc}
  #     end
  #   end)
  #   |> then(fn {%{
  #                 subdocs_added: subdocs_added,
  #                 subdocs_loaded: subdocs_loaded,
  #                 subdocs_removed: subdocs_removed
  #               } = transaction, %{subdocs: subdocs} = doc} ->
  #     if MapSet.size(subdocs_added) > 0 || MapSet.size(subdocs_removed) > 0 ||
  #          MapSet.size(subdocs_loaded) > 0 do
  #       doc_subdocs =
  #         subdocs_added
  #         |> Enum.map(fn subdoc ->
  #           %{subdoc | client_id: doc.client_id}
  #           |> case do
  #             %{collection_id: nil} -> %{subdoc | collection_id: doc.collection_id}
  #             subdoc -> subdoc
  #           end
  #         end)
  #         |> Enum.reduce(subdocs, fn new_doc, acc -> MapSet.put(acc, new_doc) end)
  #
  #       doc_subdocs =
  #         Enum.reduce(subdocs_removed, doc_subdocs, fn removed_doc, acc ->
  #           MapSet.delete(acc, removed_doc)
  #         end)
  #
  #       # doc =
  #       #   Enum.reduce(subdocs_removed, doc, fn doc_removed, doc ->
  #       #     {transaction, doc} = Doc.destroy(doc_removed, transaction)
  #       #   end)
  #
  #       {transaction, %{doc | subdocs: doc_subdocs}}
  #     else
  #       {transaction, doc}
  #     end
  #   end)
  #   |> then(fn {transaction, doc} -> cleanup(doc, rest_transactions_to_cleanup) end)
  # end
  #
  # def cleanup(doc, _, _), do: doc
  #
  # def try_gc_delete_set(
  #       %{delete_set: ds} = transaction,
  #       %{store: %Store{} = store, gc_filter: gc_filter} = doc
  #     ) do
  #   new_s_clients =
  #     for {client, delete_items} <- ds[:clients], into: %{} do
  #       # in doc, Item or GC
  #       structs = Map.get(s_cleints, client)
  #
  #       new_structs =
  #         delete_items
  #         |> Enum.reverse()
  #         |> Enum.reduce(structs, fn %{clock: delete_item_clock, len: delete_item_len}, structs ->
  #           end_delete_item_clock = delete_item_clock + delete_item_len
  #
  #           Enum.map(structs, fn s ->
  #             if s.id.clock >= delete_item_clock && s.id.clock < end_delete_item_clock &&
  #                  s.__struct__ == Item && s.deleted && !s.keep && gc_filter.(s) do
  #               Item.gc(s, false)
  #             else
  #               s
  #             end
  #           end)
  #         end)
  #
  #       {client, new_structs}
  #     end
  #
  #   d = %{doc | store: %{store | clients: new_s_clients}}
  #   {transaction, d}
  # end
  #
  # def try_merge_delete_set(
  #       %{delete_set: ds} = transaction,
  #       %{store: %Store{} = store} = doc
  #     ) do
  #   new_s_clients =
  #     for {client, delete_items} <- ds[:clients], into: %{} do
  #       # in doc, Item or GC
  #       structs = Map.get(s_cleints, client)
  #
  #       new_structs =
  #         delete_items
  #         |> Enum.reverse()
  #         |> Enum.reduce(fn delete_item ->
  #           # start with merging the item next to the last deleted item
  #           structs
  #           |> Enum.chunk_by(fn s -> s.clock < delete_item.clock + delete_item.len - 1 end)
  #           |> then(fn [left, right] ->
  #             (left ++ Enum.chunk_by(right, fn e -> {e.deleted, e.__struct__} end))
  #             |> Enum.flat_map(fn
  #               [] -> []
  #               [_] = one -> one
  #               many -> merge_with_lefts(doc, many)
  #             end)
  #           end)
  #         end)
  #
  #       {client, new_structs}
  #     end
  #
  #   d = %{doc | store: %{store | clients: new_s_clients}}
  #   {transaction, d}
  # end
  #
  # def merge_with_lefts(_doc, []), do: []
  #
  # def merge_with_lefts(_doc, structs) do
  #   [first_struct | rest_structs] = Enum.reverse(structs)
  #
  #   Enum.reduce(rest_structs, {[first_struct], true}, fn
  #     s, {acc, false} ->
  #       [s | acc]
  #
  #     s, {[to_merge_with | acc_rest] = acc, true} ->
  #       case Item.merge_with(s, to_merge_with) do
  #         nil ->
  #           {[s | acc], false}
  #
  #         new ->
  #           if to_merge_with.parentSub do
  #             Map.update_child!(to_merge_with, new)
  #           end
  #
  #           {[new | acc_rest], true}
  #       end
  #   end)
  # end
end
