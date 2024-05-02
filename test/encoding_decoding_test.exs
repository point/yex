defmodule Y.EncodingDecodingTest do
  use ExUnit.Case

  alias Y.Doc
  alias Y.Type.Array
  alias Y.Type.Map, as: TMap
  alias Y.Decoder
  alias Y.Encoder
  alias Y.Transaction

  setup_all do
    js_msg =
      <<0, 0, 6, 212, 199, 248, 185, 16, 0, 1, 0, 0, 3, 8, 0, 131, 7, 5, 97, 114, 114, 97, 121, 5,
        1, 1, 0, 1, 1, 1, 2, 0, 119, 2, 104, 105, 1, 0, 0>>

    %{js_msg: js_msg}
  end

  test "decode message from js", %{js_msg: js_msg} do
    {:ok, doc} = Doc.new(name: :decode_message_from_js)
    {:ok, doc_instance} = Doc.get_instance(doc)
    %Transaction{} = transaction = Transaction.new(doc_instance, nil, true)
    %Transaction{} = transaction = Decoder.apply(js_msg, transaction)

    assert {:ok,
            %Y.Type.Unknown{
              name: "array",
              items: [
                %Y.Item{
                  id: %Y.ID{},
                  length: 1,
                  content: ["hi"],
                  parent_name: "array",
                  deleted?: false,
                  keep?: true
                },
                %Y.Item{
                  id: %Y.ID{},
                  length: 1,
                  content: [%Y.Content.Binary{content: <<0>>}],
                  origin: %Y.ID{},
                  right_origin: nil,
                  parent_name: "array",
                  deleted?: false,
                  keep?: true
                }
              ]
            }} = Doc.get(transaction, "array")
  end

  test "decode js message with delete set" do
    msg =
      <<0, 0, 6, 229, 230, 215, 150, 3, 1, 2, 8, 2, 0, 5, 8, 0, 129, 0, 136, 7, 5, 97, 114, 114,
        97, 121, 5, 1, 1, 0, 3, 5, 1, 4, 1, 3, 0, 125, 0, 125, 1, 125, 2, 125, 3, 125, 4, 125, 6,
        125, 7, 125, 8, 125, 9, 1, 165, 243, 171, 203, 1, 1, 5, 0>>

    {:ok, doc} = Doc.new(name: :decode_message_from_js_ds)
    {:ok, _array} = Doc.get_array(doc, "array")

    assert {:ok, _} =
             Doc.transact(doc, fn transaction ->
               {:ok, Doc.apply_update(transaction, msg)}
             end)

    {:ok, array} = Doc.get(doc, "array")
    assert [0, 1, 2, 3, 4, 6, 7, 8, 9] = Array.to_list(array)

    with_deleted = Array.to_list(array, as_items: true, with_deleted: true)
    assert 10 = length(with_deleted)

    assert %Y.Item{
             id: %Y.ID{client: 426_441_125, clock: 5},
             length: 1,
             content: [%Y.Content.Deleted{len: 1}],
             origin: %Y.ID{client: 426_441_125, clock: 4},
             right_origin: nil,
             parent_name: "array",
             deleted?: true
           } = Enum.find(with_deleted, & &1.deleted?)
  end

  test "decode and integrate into separate array", %{js_msg: js_msg} do
    {:ok, doc} = Doc.new(name: :decode_into_separate)
    {:ok, array} = Doc.get_array(doc, "existing_array")

    assert {:ok, integrated_array} =
             doc
             |> Doc.transact!(fn transaction ->
               with {:ok, _array, transaction} <-
                      Array.put(array, transaction, 0, 1)
                      |> Array.put_many(1, [0, 2, 3, 4, 5, 6, 7])
                      |> Array.put_many(9, [0, 8, 9, 10, 11, 12, 13]) do
                 {:ok, transaction}
               end
             end)
             |> Doc.transact!(fn transaction ->
               {:ok, Doc.apply_update(transaction, js_msg)}
             end)
             |> Doc.get_array("array")

    assert ["hi", %Y.Content.Binary{content: <<0>>}] = Array.to_list(integrated_array)
  end

  test "decode and integrate into existing array", %{js_msg: js_msg} do
    {:ok, doc} = Doc.new(name: :decode_into_existing)
    {:ok, array} = Doc.get_array(doc, "array")

    assert {:ok, integrated_array} =
             doc
             |> Doc.transact!(fn transaction ->
               with {:ok, _array, transaction} <-
                      Array.put(array, transaction, 0, 1)
                      |> Array.put_many(1, [0, 1, 2, 3]) do
                 {:ok, transaction}
               end
             end)
             |> Doc.transact!(fn transaction ->
               {:ok, Doc.apply_update(transaction, js_msg)}
             end)
             |> Doc.get("array")

    assert [
             %Y.Item{
               content: [1],
               deleted?: false,
               id: %Y.ID{client: _, clock: 0},
               keep?: true,
               length: 1,
               origin: nil,
               parent_name: "array",
               parent_sub: nil,
               right_origin: nil
             },
             %Y.Item{
               content: [0],
               deleted?: false,
               id: %Y.ID{client: _, clock: 1},
               keep?: true,
               length: 1,
               origin: %Y.ID{client: _, clock: 0},
               parent_name: "array",
               parent_sub: nil,
               right_origin: nil
             },
             %Y.Item{
               content: [1],
               deleted?: false,
               id: %Y.ID{client: _, clock: 2},
               keep?: true,
               length: 1,
               origin: %Y.ID{client: _, clock: 1},
               parent_name: "array",
               parent_sub: nil,
               right_origin: nil
             },
             %Y.Item{
               content: [2],
               deleted?: false,
               id: %Y.ID{client: _, clock: 3},
               keep?: true,
               length: 1,
               origin: %Y.ID{client: _, clock: 2},
               parent_name: "array",
               parent_sub: nil,
               right_origin: nil
             },
             %Y.Item{
               id: %Y.ID{client: _, clock: 4},
               length: 1,
               content: [3],
               origin: %Y.ID{client: _, clock: 3},
               right_origin: nil,
               parent_name: "array",
               parent_sub: nil,
               deleted?: false,
               keep?: true
             },
             %Y.Item{
               id: %Y.ID{client: 2_208_240_084, clock: 0},
               length: 1,
               content: ["hi"],
               origin: nil,
               right_origin: nil,
               parent_name: "array",
               parent_sub: nil,
               deleted?: false,
               keep?: true
             },
             %Y.Item{
               id: %Y.ID{client: 2_208_240_084, clock: 1},
               length: 1,
               content: [%Y.Content.Binary{content: <<0>>}],
               origin: %Y.ID{client: 2_208_240_084, clock: 0},
               right_origin: nil,
               parent_name: "array",
               parent_sub: nil,
               deleted?: false,
               keep?: true
             }
           ] = Array.to_list(integrated_array, as_items: true)
  end

  test "encode and integrate itself into another doc" do
    {:ok, doc} = Doc.new(name: :encode)
    {:ok, doc2} = Doc.new(name: :decode)
    {:ok, array} = Doc.get_array(doc, "array")

    assert [
             %Y.Item{
               id: %Y.ID{client: _, clock: 0},
               length: 1,
               content: ["qwe"],
               origin: nil,
               right_origin: nil,
               parent_name: "array",
               parent_sub: nil,
               deleted?: false,
               keep?: true
             },
             %Y.Item{
               id: %Y.ID{client: _, clock: 1},
               length: 1,
               content: [%Y.Content.Binary{content: <<1>>}],
               origin: %Y.ID{client: _, clock: 0},
               right_origin: nil,
               parent_name: "array",
               parent_sub: nil,
               deleted?: false,
               keep?: true
             }
           ] =
             doc
             |> Doc.transact!(fn transaction ->
               with {:ok, _array, transaction} <-
                      Array.put(array, transaction, 0, "qwe")
                      |> Array.put(1, Y.Content.Binary.new(<<1>>)) do
                 {:ok, transaction}
               end
             end)
             |> Encoder.encode()
             |> then(fn msg ->
               doc2
               |> Doc.transact!(fn transaction ->
                 {:ok, Doc.apply_update(transaction, msg)}
               end)
               |> Doc.get_array("array")
               |> elem(1)
             end)
             |> Array.to_list(as_items: true)
  end

  test "encode and integrate itself into another doc, check origin/right_origin" do
    {:ok, doc} = Doc.new(name: :encode_origin)
    {:ok, doc2} = Doc.new(name: :decode_origin)
    {:ok, array} = Doc.get_array(doc, "array")

    assert [
             %Y.Item{
               id: %Y.ID{client: _, clock: 1},
               length: 1,
               content: [%Y.Content.Binary{content: <<1>>}],
               origin: nil,
               right_origin: %Y.ID{client: _, clock: 0},
               parent_name: "array",
               parent_sub: nil,
               deleted?: false,
               keep?: true
             },
             %Y.Item{
               content: ["hi"],
               deleted?: false,
               id: %Y.ID{client: _, clock: 0},
               keep?: true,
               length: 1,
               origin: nil,
               parent_name: "array",
               parent_sub: nil,
               right_origin: nil
             },
             %Y.Item{
               content: [%Y.Content.Binary{content: "zxc"}],
               deleted?: false,
               id: %Y.ID{client: _, clock: 2},
               keep?: true,
               length: 1,
               origin: %Y.ID{client: _, clock: 0},
               parent_name: "array",
               parent_sub: nil,
               right_origin: nil
             }
           ] =
             doc
             |> Doc.transact!(fn transaction ->
               with {:ok, _array, transaction} <-
                      Array.put(array, transaction, 0, "hi")
                      |> Array.put(0, Y.Content.Binary.new(<<1>>))
                      |> Array.put(2, Y.Content.Binary.new("zxc")) do
                 {:ok, transaction}
               end
             end)
             |> Encoder.encode()
             |> then(fn msg ->
               doc2
               |> Doc.transact!(fn transaction ->
                 {:ok, Doc.apply_update(transaction, msg)}
               end)
               |> Doc.get_array("array")
               |> elem(1)
             end)
             |> Array.to_list(as_items: true)
  end

  test "check delete sets, one element" do
    {:ok, doc1} = Doc.new(name: :encode_origin2)
    {:ok, doc2} = Doc.new(name: :decode_origin2)
    {:ok, array1} = Doc.get_array(doc1, "array")
    {:ok, _array2} = Doc.get_array(doc2, "array")

    msg =
      doc1
      |> Doc.transact!(fn transaction ->
        {:ok, _array, transaction} =
          Array.put(array1, transaction, 0, 0)

        {:ok, transaction}
      end)
      |> Encoder.encode()

    doc2
    |> Doc.transact!(fn transaction ->
      {:ok, Doc.apply_update(transaction, msg)}
    end)

    assert {:ok, _array2} = Doc.get(doc2, "array")

    msg2 =
      doc1
      |> Doc.transact!(fn transaction ->
        {:ok, array1} = Doc.get(transaction, "array")

        {:ok, _array, transaction} =
          Array.delete(array1, transaction, 0)

        {:ok, transaction}
      end)
      |> Encoder.encode()

    doc2
    |> Doc.transact!(fn transaction ->
      {:ok, Doc.apply_update(transaction, msg2)}
    end)

    assert {:ok, array2} = Doc.get(doc2, "array")

    assert [%Y.Item{deleted?: true, content: [0]}] =
             Array.to_list(array2, as_items: true, with_deleted: true)
  end

  test "check delete sets, few elements" do
    {:ok, doc1} = Doc.new(name: :ds_few1)
    {:ok, doc2} = Doc.new(name: :ds_few2)
    {:ok, array1} = Doc.get_array(doc1, "array")
    {:ok, _array2} = Doc.get_array(doc2, "array")

    msg =
      doc1
      |> Doc.transact!(fn transaction ->
        {:ok, _array, transaction} =
          Array.put_many(array1, transaction, 0, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9])

        {:ok, transaction}
      end)
      |> Encoder.encode()

    doc2
    |> Doc.transact!(fn transaction ->
      {:ok, Doc.apply_update(transaction, msg)}
    end)

    assert {:ok, array2} = Doc.get(doc2, "array")
    assert Enum.to_list(0..9) == Array.to_list(array2)

    msg2 =
      doc1
      |> Doc.transact!(fn transaction ->
        {:ok, array1} = Doc.get(transaction, "array")

        {:ok, _array1, transaction} =
          Array.delete(array1, transaction, 5)

        {:ok, transaction}
      end)
      |> Encoder.encode()

    doc2
    |> Doc.transact!(fn transaction ->
      {:ok, Doc.apply_update(transaction, msg2)}
    end)

    assert {:ok, array2} = Doc.get(doc2, "array")

    {:ok, doc1_instance} = Doc.get_instance(doc1)
    client_id = doc1_instance.client_id

    assert %Y.Item{content: [5], id: %{client: ^client_id}} =
             array2
             |> Array.to_list(as_items: true, with_deleted: true)
             |> Enum.find(& &1.deleted?)

    assert Enum.count(array2) == 9
  end

  test "decode with maps" do
    msg =
      <<0, 0, 6, 195, 138, 230, 232, 9, 3, 4, 1, 0, 6, 0, 0, 7, 39, 0, 40, 1, 39, 0, 40, 46, 37,
        109, 97, 112, 48, 109, 49, 110, 117, 109, 98, 101, 114, 115, 116, 114, 105, 110, 103, 109,
        97, 112, 48, 109, 50, 111, 98, 106, 101, 99, 116, 98, 111, 111, 108, 101, 97, 110, 4, 2,
        70, 0, 4, 2, 6, 7, 7, 1, 0, 0, 1, 1, 0, 0, 2, 65, 0, 2, 65, 2, 1, 6, 0, 125, 1, 119, 5,
        104, 101, 108, 108, 111, 118, 1, 1, 120, 125, 1, 120, 0>>

    {:ok, doc} = Doc.new(name: :decode_with_maps)

    assert {:ok, _} =
             Doc.transact(doc, fn transaction ->
               {:ok, Doc.apply_update(transaction, msg)}
             end)

    {:ok, map0} = Doc.get_map(doc, "map0")

    assert [
             %Y.Item{
               id: %Y.ID{client: 1_317_847_683, clock: 3},
               length: 1,
               content: [
                 %Y.Type.Map{
                   doc_name: :decode_with_maps,
                   name: _
                 }
               ],
               parent_name: "map0",
               parent_sub: "m2",
               deleted?: false
             } = top,
             %Y.Item{
               id: %Y.ID{client: 1_317_847_683, clock: 0},
               length: 1,
               content: [
                 %Y.Type.Map{
                   doc_name: :decode_with_maps,
                   name: _
                 }
               ],
               parent_name: "map0",
               parent_sub: "m1",
               deleted?: false
             }
           ] = TMap.to_list(map0, as_items: true)

    assert ["m1", "m2"] = TMap.keys(map0)

    assert %TMap{} = m1 = TMap.get(map0, "m1")
    assert ["number", "string"] = TMap.keys(m1)
    assert 1 == TMap.get(m1, "number")
    assert "hello" == TMap.get(m1, "string")

    assert [
             %Y.Item{
               id: %Y.ID{client: 1_317_847_683, clock: 2},
               length: 1,
               content: ["hello"],
               parent_name: _,
               parent_sub: "string",
               deleted?: false
             },
             %Y.Item{
               id: %Y.ID{client: 1_317_847_683, clock: 1},
               length: 1,
               content: [1],
               parent_name: _,
               parent_sub: "number",
               deleted?: false
             }
           ] = TMap.to_list(m1, as_items: true)

    assert %TMap{} = m2 = TMap.get(map0, "m2")
    assert ["boolean", "object"] = TMap.keys(m2)
    assert true === TMap.get(m2, "boolean")
    assert %{"x" => 1} = TMap.get(m2, "object")

    assert [
             %Y.Item{
               id: %Y.ID{client: 1_317_847_683, clock: 4},
               length: 1,
               content: [%{"x" => 1}],
               parent_name: _,
               parent_sub: "object",
               deleted?: false
             },
             %Y.Item{
               id: %Y.ID{client: 1_317_847_683, clock: 5},
               length: 1,
               content: [true],
               parent_name: _,
               parent_sub: "boolean",
               deleted?: false
             } = inner
           ] = TMap.to_list(m2, as_items: true)

    assert nil == Doc.find_parent_item!(doc, top)
    assert ^top = Doc.find_parent_item!(doc, inner)
  end
end
