defmodule Y.ArrayTest do
  use ExUnit.Case
  alias Y.Transaction
  alias Y.Doc
  alias Y.ID
  alias Y.Type.Array
  alias Y.Item

  test "insert" do
    {:ok, doc} = Doc.new(name: :doc1)
    {:ok, array} = Doc.get_array(doc, "array")

    doc
    |> Doc.transact(fn transaction ->
      with {:ok, array, transaction} <- Array.put(array, transaction, 0, 0),
           {:ok, array, transaction} <- Array.put(array, transaction, 1, 1),
           {:ok, array, transaction} <- Array.put(array, transaction, 0, 2),
           {:ok, array, transaction} <- Array.put(array, transaction, 1, 3) do
        assert [2, 3, 0, 1] == Array.to_list(array)
        {:ok, transaction}
      end
    end)

    {:ok, doc} = Doc.new(name: :doc2)
    {:ok, array} = Doc.get_array(doc, "array2")

    doc
    |> Doc.transact(fn transaction ->
      with {:ok, array, transaction} <- Array.put(array, transaction, 0, 0),
           {:ok, array, transaction} <- Array.put_many(array, transaction, 1, [1, 2, 3]),
           {:ok, array, transaction} <- Array.put(array, transaction, 4, 4) do
        {:ok, res_array, _} = Array.put(array, transaction, -1, 20)
        assert Array.to_list(res_array) == [20, 0, 1, 2, 3, 4]

        {:ok, res_array, _} = Array.put(array, transaction, 0, 20)
        assert Array.to_list(res_array) == [20, 0, 1, 2, 3, 4]

        # assert origin/right_origin
        assert [
                 %Y.Item{
                   id: %Y.ID{client: _, clock: 5},
                   length: 1,
                   content: [20],
                   origin: nil,
                   right_origin: %Y.ID{client: _, clock: 0},
                   parent_name: "array2",
                   parent_sub: nil,
                   deleted?: false,
                   keep?: true
                 },
                 %Y.Item{
                   id: %Y.ID{client: _, clock: 0},
                   length: 1,
                   content: [0],
                   origin: nil,
                   right_origin: nil,
                   parent_name: "array2",
                   parent_sub: nil,
                   deleted?: false,
                   keep?: true
                 },
                 %Y.Item{
                   content: [1],
                   deleted?: false,
                   id: %Y.ID{client: _, clock: 1},
                   keep?: true,
                   length: 1,
                   origin: %Y.ID{client: _, clock: 0},
                   parent_name: "array2",
                   parent_sub: nil,
                   right_origin: nil
                 },
                 %Y.Item{
                   content: [2],
                   deleted?: false,
                   id: %Y.ID{client: _, clock: 2},
                   keep?: true,
                   length: 1,
                   origin: %Y.ID{client: _, clock: 1},
                   parent_name: "array2",
                   parent_sub: nil,
                   right_origin: nil
                 },
                 %Y.Item{
                   id: %Y.ID{client: _, clock: 3},
                   length: 1,
                   content: [3],
                   origin: %Y.ID{client: _, clock: 2},
                   right_origin: nil,
                   parent_name: "array2",
                   parent_sub: nil,
                   deleted?: false,
                   keep?: true
                 },
                 %Y.Item{
                   id: %Y.ID{client: _, clock: 4},
                   length: 1,
                   content: [4],
                   origin: %Y.ID{client: _, clock: 3},
                   right_origin: nil,
                   parent_name: "array2",
                   parent_sub: nil,
                   deleted?: false,
                   keep?: true
                 }
               ] = Array.to_list(res_array, as_items: true)

        {:ok, res_array, _} = Array.put(array, transaction, 1, 20)
        assert Array.to_list(res_array) == [0, 20, 1, 2, 3, 4]

        {:ok, res_array, _} = Array.put(array, transaction, 2, 20)
        assert Array.to_list(res_array) == [0, 1, 20, 2, 3, 4]

        {:ok, res_array, _} = Array.put(array, transaction, 3, 20)
        assert Array.to_list(res_array) == [0, 1, 2, 20, 3, 4]

        {:ok, res_array, _} = Array.put(array, transaction, 4, 20)
        assert Array.to_list(res_array) == [0, 1, 2, 3, 20, 4]

        {:ok, res_array, _} = Array.put(array, transaction, 5, 20)
        assert Array.to_list(res_array) == [0, 1, 2, 3, 4, 20]

        {:ok, res_array, _} = Array.put(array, transaction, 6, 20)
        assert Array.to_list(res_array) == [0, 1, 2, 3, 4, 20]

        {:ok, _res_array, transaction} = Array.put(array, transaction, 3, 20)

        {:ok, transaction}
      end
    end)
  end

  test "pack plain" do
    item1 = %Y.Item{
      id: %Y.ID{client: 1092, clock: 0},
      length: 1,
      content: [0],
      origin: nil,
      right_origin: nil,
      parent_name: "array_pack",
      parent_sub: nil,
      deleted?: false,
      keep?: true
    }

    item2 = %Y.Item{
      id: %Y.ID{client: 1092, clock: 1},
      length: 1,
      content: [1],
      origin: %Y.ID{client: 1092, clock: 0},
      right_origin: nil,
      parent_name: "array_pack",
      parent_sub: nil,
      deleted?: false,
      keep?: true
    }

    assert true == Item.mergeable?(item1, item2)
  end

  test "pack" do
    {:ok, doc} = Doc.new(name: :doc_pack)
    {:ok, array} = Doc.get_array(doc, "array_pack")

    assert [
             %Y.Item{
               id: %Y.ID{client: _, clock: 0},
               length: 6,
               content: [0, 1, 2, 3, 4, 5],
               origin: nil,
               right_origin: nil,
               parent_name: "array_pack",
               parent_sub: nil,
               deleted?: false,
               keep?: true
             },
             %Y.Item{
               id: %Y.ID{client: _, clock: 6},
               length: 1,
               content: [%Y.Content.Binary{content: <<1>>}],
               origin: %Y.ID{client: _, clock: 5},
               right_origin: nil,
               parent_name: "array_pack",
               parent_sub: nil,
               deleted?: false,
               keep?: true
             }
           ] =
             doc
             |> Doc.transact!(fn transaction ->
               with {:ok, _array, transaction} <-
                      Array.put(array, transaction, 0, 0)
                      |> Array.put(1, 1)
                      |> Array.put_many(2, [2, 3, 4, 5])
                      |> Array.put(6, Y.Content.Binary.new(<<1>>)) do
                 {:ok, Transaction.force_pack(transaction)}
               end
             end)
             |> Doc.get("array_pack")
             |> elem(1)
             |> Array.to_list(as_items: true)
  end

  test "find" do
    {:ok, doc} = Doc.new(name: :doc_find)
    {:ok, array} = Doc.get_array(doc, "array")

    doc
    |> Doc.transact(fn transaction ->
      with {:ok, array, transaction} <-
             Array.put(array, transaction, 0, 1)
             |> Array.put(1, 2)
             |> Array.put(2, 3)
             |> Array.put(3, 4)
             |> Array.put(4, 5) do
        [%{id: %{client: client}} | _] = Array.to_list(array, as_items: true)
        id = ID.new(client, 3)
        assert %{id: ^id} = Array.find(array, id)
        {:ok, transaction}
      end
    end)
  end

  test "find in the middle" do
    {:ok, doc} = Doc.new(name: :doc_find2)
    {:ok, array} = Doc.get_array(doc, "array")

    doc
    |> Doc.transact(fn transaction ->
      with {:ok, array, transaction} <-
             Array.put(array, transaction, 0, 1)
             |> Array.put_many(1, [0, 2, 3, 4, 5, 6, 7])
             |> Array.put_many(9, [0, 8, 9, 10, 11, 12, 13]) do
        [%{id: %{client: client}} | _] = Array.to_list(array, as_items: true)
        id = ID.new(client, 2)
        assert %{id: ^id, content: [2]} = Array.find(array, id)

        # at boundary
        id = ID.new(client, 7)
        assert %{id: ^id, content: [7]} = Array.find(array, id)

        # next entry
        id = ID.new(client, 8)
        assert %{id: ^id, content: [0]} = Array.find(array, id)

        {:ok, transaction}
      end
    end)
  end

  test "between" do
    {:ok, doc} = Doc.new(name: :doc_find3)
    {:ok, array} = Doc.get_array(doc, "array")

    assert {:ok, array} =
             doc
             |> Doc.transact!(fn transaction ->
               with {:ok, _array, transaction} <-
                      Enum.reduce(1..20, Array.put(array, transaction, 0, 0), fn i, acc ->
                        Array.put(acc, i, i)
                      end) do
                 {:ok, transaction}
               end
             end)
             |> Doc.get("array")

    [%{id: %{client: client}} | _] = Array.to_list(array, as_items: true)
    # between excludes the right boundary (like Y.js), so between(3, 7) returns items 3, 4, 5, 6
    items = Array.between(array, ID.new(client, 3), ID.new(client, 7))

    assert Enum.map(items, fn %{id: %{clock: c}} -> c end) |> Enum.sort() ==
             Enum.to_list(3..6)
  end

  test "slice (Enumerable protocol)" do
    {:ok, doc} = Doc.new(name: :doc_slice)
    {:ok, array} = Doc.get_array(doc, "array")

    assert {:ok, array} =
             doc
             |> Doc.transact!(fn transaction ->
               with {:ok, _array, transaction} <-
                      Enum.reduce(1..20, Array.put(array, transaction, 0, 0), fn i, acc ->
                        Array.put(acc, i, i)
                      end) do
                 {:ok, transaction}
               end
             end)
             |> Doc.get("array")

    assert Enum.to_list(0..40//2) ==
             Enum.map(array, fn c -> c * 2 end)
  end

  test "length + at" do
    {:ok, doc} = Doc.new(name: :doc_length)
    {:ok, array} = Doc.get_array(doc, "array")
    {:ok, empty_array} = Doc.get_array(doc, "empty_array")

    assert {:ok, array} =
             doc
             |> Doc.transact!(fn transaction ->
               with {:ok, _array, transaction} <-
                      Enum.reduce(1..9, Array.put(array, transaction, 0, 0), fn i, acc ->
                        Array.put(acc, i, i)
                      end) do
                 {:ok, transaction}
               end
             end)
             |> Doc.get("array")

    assert 10 = Array.length(array)
    assert 0 = Array.length(empty_array)

    assert %Item{content: [0]} = Array.at(array, 0)
    assert %Item{content: [1]} = Array.at(array, 1)
    assert %Item{content: [9]} = Array.at(array, 9)
    assert nil == Array.at(array, 10)

    assert nil == Array.at(empty_array, 0)
    assert nil == Array.at(empty_array, 1)
  end

  test "delete" do
    {:ok, doc} = Doc.new(name: :doc_delete)
    {:ok, array} = Doc.get_array(doc, "array")

    Doc.transact(doc, fn transaction ->
      assert {:ok, _, transaction} = Array.delete(array, transaction, 0)
      {:ok, transaction}
    end)

    assert {:ok, _} =
             doc
             |> Doc.transact(fn transaction ->
               with {:ok, _array, transaction} <-
                      Enum.reduce(1..9, Array.put(array, transaction, 0, 0), fn i, acc ->
                        Array.put(acc, i, i)
                      end) do
                 {:ok, transaction}
               end
             end)

    doc
    |> Doc.transact!(fn transaction ->
      {:ok, array} = Doc.get(transaction, "array")
      {:ok, array, transaction} = Array.delete(array, transaction, 5)

      assert %Item{content: [5]} =
               Enum.find(Array.to_list(array, as_items: true, with_deleted: true), fn item ->
                 item.deleted?
               end)

      {:ok, transaction}
    end)

    assert {:ok, array} =
             doc
             |> Doc.transact!(fn transaction ->
               with {:ok, array} <- Doc.get(transaction, "array"),
                    {:ok, _array, transaction} <- Array.delete(array, transaction, 6, 8),
                    do: {:ok, transaction}
             end)
             |> Doc.get("array")

    # 5th in original array is deleted =>
    # array[6] == 7
    # array[7] == 8
    # array[8] == 9
    assert [0, 1, 2, 3, 4, 6] = Array.to_list(array)
  end

  test "enumerable protocol" do
    {:ok, doc} = Doc.new(name: :doc_enumerable)
    {:ok, array} = Doc.get_array(doc, "array")

    assert [] = Enum.slice(array, 1..3)

    assert {:ok, _} =
             Doc.transact(doc, fn transaction ->
               {:ok, array, transaction} = Array.put(array, transaction, 0, 0)
               {:ok, array, transaction} = Array.delete(array, transaction, 0)
               assert [] = Enum.slice(array, 1..3)

               {:ok, array, transaction} =
                 Array.put_many(array, transaction, 0, Enum.to_list(0..9))

               {:ok, array, transaction} = Array.delete(array, transaction, 2)
               assert [1, 3, 4] = Enum.slice(array, 1..3)

               {:ok, transaction}
             end)
  end

  test "concurrent write" do
    {:ok, doc} = Doc.new(name: :doc_concurrent)
    {:ok, _array} = Doc.get_array(doc, "array")

    t1 =
      Task.async(fn ->
        Doc.transact(doc, fn transaction ->
          assert {:ok, array} = Doc.get(transaction, "array")
          assert {:ok, _array, transaction} = Array.put(array, transaction, 0, 1)
          {:ok, transaction}
        end)
      end)

    t2 =
      Task.async(fn ->
        Doc.transact(doc, fn transaction ->
          assert {:ok, array} = Doc.get(transaction, "array")
          assert {:ok, _array, transaction} = Array.put(array, transaction, 0, 2)
          {:ok, transaction}
        end)
      end)

    Task.await_many([t1, t2])

    {:ok, array} = Doc.get(doc, "array")
    assert [1, 2] == Array.to_list(array) |> Enum.sort()
  end

  test "nested arrays" do
    {:ok, doc} = Doc.new(name: :doc_nested)
    {:ok, array} = Doc.get_array(doc, "array")
    {:ok, nested} = Doc.get_array(doc, "nested")
    {:ok, _nested2} = Doc.get_array(doc, "nested2")

    Doc.transact(doc, fn transaction ->
      {:ok, nested, transaction} = Array.put(nested, transaction, 0, 0)
      {:ok, _, transaction} = Array.put(array, transaction, 0, nested)
      {:ok, transaction}
    end)

    {:ok, array} = Doc.get(doc, "array")
    assert [0] = Enum.at(array, 0) |> Array.to_list()

    Doc.transact(doc, fn transaction ->
      {:ok, nested} = Doc.get(transaction, "nested")
      {:ok, _, transaction} = Array.put(nested, transaction, 1, 1)
      {:ok, transaction}
    end)

    {:ok, array} = Doc.get(doc, "array")
    assert [0, 1] = Enum.at(array, 0) |> Array.to_list()

    # 2 level nesting
    Doc.transact(doc, fn transaction ->
      {:ok, nested} = Doc.get(transaction, "nested")
      {:ok, nested2} = Doc.get(transaction, "nested2")
      {:ok, _, transaction} = Array.put(nested, transaction, 2, nested2)
      {:ok, transaction}
    end)

    Doc.transact(doc, fn transaction ->
      {:ok, nested2} = Doc.get(transaction, "nested2")
      {:ok, _, transaction} = Array.put(nested2, transaction, 0, 2)
      {:ok, transaction}
    end)

    {:ok, array} = Doc.get(doc, "array")
    assert 2 == Enum.at(array, 0) |> Enum.at(2) |> Enum.at(0)
  end

  test "map in array" do
    {:ok, doc} = Doc.new(name: :map_nested)
    {:ok, array} = Doc.get_array(doc, "array")
    {:ok, map} = Doc.get_map(doc, "map")

    Doc.transact(doc, fn transaction ->
      {:ok, map, transaction} = Y.Type.Map.put(map, transaction, "key", "value")
      {:ok, _, transaction} = Array.put(array, transaction, 0, map)
      {:ok, transaction}
    end)

    {:ok, array} = Doc.get(doc, "array")
    assert %Y.Type.Map{} = map = Enum.at(array, 0)
    assert "value" = Y.Type.Map.get(map, "key")

    Doc.transact(doc, fn transaction ->
      {:ok, map} = Doc.get(transaction, "map")
      {:ok, _, transaction} = Y.Type.Map.put(map, transaction, "key", "new_value")
      {:ok, transaction}
    end)

    {:ok, array} = Doc.get(doc, "array")
    %Y.Type.Map{} = map = Enum.at(array, 0)
    assert "new_value" = Y.Type.Map.get(map, "key")
  end

  test "length + delete" do
    {:ok, doc} = Doc.new(name: :array_length)
    {:ok, array} = Doc.get_array(doc, "array")

    doc
    |> Doc.transact(fn transaction ->
      {:ok, array, transaction} =
        Array.put(array, transaction, 0, 0)
        |> Array.put(1, 1)
        |> Array.put_many(2, [2, 3, 4])

      assert 5 = Array.length(array)

      assert {:ok, array, transaction} = Array.delete(array, transaction, 0)
      assert 4 = Array.length(array)

      assert {:ok, array, transaction} = Array.delete(array, transaction, 0, 4)
      assert 0 = Array.length(array)

      {:ok, transaction}
    end)
  end
end
