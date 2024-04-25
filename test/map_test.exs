defmodule Y.MapTest do
  use ExUnit.Case
  # alias Y.Transaction
  alias Y.Doc
  alias Y.Type.Map, as: TMap
  # alias Y.ID
  alias Y.Type.Array
  alias Y.Item

  test "insert" do
    {:ok, doc} = Doc.new(name: :map_insert)
    {:ok, _map} = Doc.get_map(doc, "map")

    Doc.transact(doc, fn transaction ->
      {:ok, map} = Doc.get(transaction, "map")
      {:ok, _, transaction} = Y.Type.Map.put(map, transaction, "key", [1, 2, 3])
      {:ok, transaction}
    end)

    {:ok, map} = Doc.get(doc, "map")
    assert [1, 2, 3] == TMap.get(map, "key")
    assert %Item{content: [[1, 2, 3]]} = TMap.get_item(map, "key")
  end

  test "insert into array" do
    {:ok, doc} = Doc.new(name: :map_insert_array)
    {:ok, array} = Doc.get_array(doc, "array")
    {:ok, map} = Doc.get_map(doc, "map")

    Doc.transact(doc, fn transaction ->
      {:ok, map, transaction} =
        TMap.put(map, transaction, "key", [1, 2, 3])
        |> TMap.put("key2", %{})

      {:ok, _, transaction} =
        Array.put(array, transaction, 0, 0)
        |> Array.put(1, map)

      {:ok, transaction}
    end)

    {:ok, array} = Doc.get(doc, "array")
    assert [_, %TMap{}] = Array.to_list(array)

    Doc.transact(doc, fn transaction ->
      {:ok, map} = Doc.get(transaction, "map")
      {:ok, _, transaction} = Y.Type.Map.put(map, transaction, "other key", 123)
      {:ok, transaction}
    end)

    {:ok, array} = Doc.get(doc, "array")
    assert [_, map_from_list] = Array.to_list(array)
    assert [{"other key", 123}, {"key2", %{}}, {"key", [1, 2, 3]}] = TMap.to_list(map_from_list)

    assert TMap.has_key?(map_from_list, "other key")
    refute TMap.has_key?(map_from_list, "zzz")

    assert ["key", "key2", "other key"] = TMap.keys(map_from_list)
  end

  test "map in map" do
    {:ok, doc} = Doc.new(name: :map_in_map)
    {:ok, map0} = Doc.get_map(doc, "map0")
    {:ok, map1} = Doc.get_map(doc, "map1")

    Doc.transact(doc, fn transaction ->
      {:ok, map1, transaction} = Y.Type.Map.put(map1, transaction, "number key", 1)
      {:ok, _, transaction} = Y.Type.Map.put(map0, transaction, "m1", map1)
      {:ok, transaction}
    end)

    {:ok, map0} = Doc.get(doc, "map0")
  end
end
