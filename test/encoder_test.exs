defmodule Y.EncoderTest do
  use ExUnit.Case
  alias Y.Doc
  alias Y.Type.Array
  alias Y.Encoder

  test "without_deletions" do
    {:ok, doc} = Doc.new(name: :doc1)
    {:ok, array} = Doc.get_array(doc, "array")

    doc
    |> Doc.transact(fn transaction ->
      with {:ok, array, transaction} <- Array.put(array, transaction, 0, 0),
           {:ok, array, transaction} <- Array.put(array, transaction, 1, 1),
           {:ok, array, transaction} <- Array.put(array, transaction, 0, 2),
           {:ok, _array, transaction} <- Array.put(array, transaction, 1, 3) do
        {:ok, transaction}
      end
    end)

    assert <<0, _rest::binary>> = Encoder.encode(doc)
  end
end
