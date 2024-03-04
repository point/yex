defmodule Y.EncodingDecodingTest do
  use ExUnit.Case

  alias Y.Doc
  alias Y.Type.Array
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
    transaction = Transaction.new(doc_instance, nil, true)
    transaction = Decoder.decode(js_msg, transaction)

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
               {:ok, Decoder.decode(js_msg, transaction)}
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
               {:ok, Decoder.decode(js_msg, transaction)}
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
                 {:ok, Decoder.decode(msg, transaction)}
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
                 {:ok, Decoder.decode(msg, transaction)}
               end)
               |> Doc.get_array("array")
               |> elem(1)
             end)
             |> Array.to_list(as_items: true)
  end
end
