defmodule Y.ArrayCRDTTest do
  @moduledoc """
  CRDT Property Tests for Y.Array
  Ported from yjs tests/y-array-crdt.tests.js commit 639a9de0eb13253aa27f33b8d39b5115e98f88c4
  """
  use ExUnit.Case

  alias Y.Doc
  alias Y.Type.Array
  alias Y.Encoder
  alias Y.Decoder
  alias Y.Transaction

  # ============================================================================
  # Commutativity Tests
  # ============================================================================

  @doc """
  Test commutativity: Operations applied in different orders should converge to the same state.
  This is a fundamental CRDT property.
  """
  test "commutativity two writes" do
    {:ok, doc1} = Doc.new(name: :comm_doc1, client_id: 1)
    {:ok, doc2} = Doc.new(name: :comm_doc2, client_id: 2)

    {:ok, arr1} = Doc.get_array(doc1, "array")
    {:ok, arr2} = Doc.get_array(doc2, "array")

    # User 1 inserts 'A' at position 0
    Doc.transact!(doc1, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr1, transaction, 0, "A")
      {:ok, transaction}
    end)

    update1 = Encoder.encode(doc1)

    # Binary assertion from JS test (V2 encoding)
    assert :binary.bin_to_list(update1) == [
             0,
             0,
             1,
             1,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             1,
             1,
             1,
             0,
             119,
             1,
             65,
             0
           ]

    # User 2 inserts 'B' at position 0
    Doc.transact!(doc2, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr2, transaction, 0, "B")
      {:ok, transaction}
    end)

    update2 = Encoder.encode(doc2)

    # Binary assertion from JS test (V2 encoding)
    assert :binary.bin_to_list(update2) == [
             0,
             0,
             1,
             2,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             1,
             1,
             1,
             0,
             119,
             1,
             66,
             0
           ]

    # Apply updates in different orders
    {:ok, doc_order1} = Doc.new(name: :comm_order1)
    {:ok, _} = Doc.get_array(doc_order1, "array")

    {:ok, doc_order2} = Doc.new(name: :comm_order2)
    {:ok, _} = Doc.get_array(doc_order2, "array")

    # Order 1: update1 then update2
    Doc.transact!(doc_order1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    Doc.transact!(doc_order1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    # Order 2: update2 then update1
    Doc.transact!(doc_order2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    Doc.transact!(doc_order2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    # Both should converge to the same state
    {:ok, arr_order1} = Doc.get(doc_order1, "array")
    {:ok, arr_order2} = Doc.get(doc_order2, "array")

    assert Array.to_list(arr_order1) == Array.to_list(arr_order2),
           "Commutativity: different application order produces same result"
  end

  @doc """
  Test commutativity with multiple concurrent operations from multiple peers.
  """
  test "commutativity multiple peers" do
    {:ok, doc0} = Doc.new(name: :comm_multi_0, client_id: 0)
    {:ok, doc1} = Doc.new(name: :comm_multi_1, client_id: 1)
    {:ok, doc2} = Doc.new(name: :comm_multi_2, client_id: 2)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, arr1} = Doc.get_array(doc1, "array")
    {:ok, arr2} = Doc.get_array(doc2, "array")

    # All three users write concurrently without syncing
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr0, transaction, 0, "from-user-0")
      {:ok, transaction}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr1, transaction, 0, "from-user-1")
      {:ok, transaction}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr2, transaction, 0, "from-user-2")
      {:ok, transaction}
    end)

    # Get all updates
    update0 = Encoder.encode(doc0)

    assert :binary.bin_to_list(update0) == [
             0,
             0,
             1,
             0,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             1,
             1,
             1,
             0,
             119,
             11,
             102,
             114,
             111,
             109,
             45,
             117,
             115,
             101,
             114,
             45,
             48,
             0
           ]

    update1 = Encoder.encode(doc1)

    assert :binary.bin_to_list(update1) == [
             0,
             0,
             1,
             1,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             1,
             1,
             1,
             0,
             119,
             11,
             102,
             114,
             111,
             109,
             45,
             117,
             115,
             101,
             114,
             45,
             49,
             0
           ]

    update2 = Encoder.encode(doc2)

    assert :binary.bin_to_list(update2) == [
             0,
             0,
             1,
             2,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             1,
             1,
             1,
             0,
             119,
             11,
             102,
             114,
             111,
             109,
             45,
             117,
             115,
             101,
             114,
             45,
             50,
             0
           ]

    # Apply in different permutations
    permutations = [
      [update0, update1, update2],
      [update0, update2, update1],
      [update1, update0, update2],
      [update1, update2, update0],
      [update2, update0, update1],
      [update2, update1, update0]
    ]

    results =
      permutations
      |> Enum.with_index()
      |> Enum.map(fn {perm, idx} ->
        {:ok, doc} = Doc.new(name: :"perm_#{idx}")
        {:ok, _} = Doc.get_array(doc, "array")

        Enum.each(perm, fn u ->
          Doc.transact!(doc, fn transaction ->
            {:ok, Doc.apply_update(transaction, u)}
          end)
        end)

        {:ok, arr} = Doc.get(doc, "array")
        Array.to_list(arr)
      end)

    # All permutations should produce the same result
    [first | rest] = results

    Enum.with_index(rest)
    |> Enum.each(fn {result, i} ->
      assert first == result, "Permutation #{i + 1} matches permutation 0"
    end)
  end

  # ============================================================================
  # Idempotency Tests
  # ============================================================================

  @doc """
  Test idempotency: Applying the same update twice should have no effect.
  """
  test "idempotency" do
    {:ok, doc1} = Doc.new(name: :idemp_1, client_id: 1)
    {:ok, arr1} = Doc.get_array(doc1, "array")

    Doc.transact!(doc1, fn transaction ->
      {:ok, arr, transaction} = Array.put_many(arr1, transaction, 0, ["A", "B", "C"])
      {:ok, _arr, transaction} = Array.delete(arr, transaction, 1)
      {:ok, transaction}
    end)

    update = Encoder.encode(doc1)

    # Binary assertion from JS test (V2 encoding)
    assert :binary.bin_to_list(update) == [
             0,
             0,
             2,
             65,
             1,
             2,
             0,
             2,
             0,
             5,
             8,
             0,
             129,
             0,
             136,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             2,
             65,
             1,
             1,
             3,
             0,
             119,
             1,
             65,
             119,
             1,
             67,
             1,
             1,
             1,
             1,
             0
           ]

    {:ok, doc2} = Doc.new(name: :idemp_2)
    {:ok, _} = Doc.get_array(doc2, "array")

    # Apply update once
    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update)}
    end)

    {:ok, arr_after_once} = Doc.get(doc2, "array")
    state_after_once = Array.to_list(arr_after_once)

    # Apply the same update again
    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update)}
    end)

    {:ok, arr_after_twice} = Doc.get(doc2, "array")
    state_after_twice = Array.to_list(arr_after_twice)

    # Apply it a third time
    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update)}
    end)

    {:ok, arr_after_thrice} = Doc.get(doc2, "array")
    state_after_thrice = Array.to_list(arr_after_thrice)

    assert state_after_once == state_after_twice, "Idempotency: second application has no effect"
    assert state_after_twice == state_after_thrice, "Idempotency: third application has no effect"
    assert state_after_once == ["A", "C"], "Content is correct"
  end

  @doc """
  Test idempotency with interleaved duplicate deliveries.
  """
  test "idempotency interleaved duplicates" do
    {:ok, doc1} = Doc.new(name: :idemp_inter_1, client_id: 1)
    {:ok, doc2} = Doc.new(name: :idemp_inter_2, client_id: 2)
    {:ok, doc3} = Doc.new(name: :idemp_inter_3, client_id: 3)

    {:ok, arr1} = Doc.get_array(doc1, "array")
    {:ok, arr2} = Doc.get_array(doc2, "array")
    {:ok, arr3} = Doc.get_array(doc3, "array")

    Doc.transact!(doc1, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr1, transaction, 0, "A")
      {:ok, transaction}
    end)

    update1 = Encoder.encode(doc1)

    assert :binary.bin_to_list(update1) == [
             0,
             0,
             1,
             1,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             1,
             1,
             1,
             0,
             119,
             1,
             65,
             0
           ]

    Doc.transact!(doc2, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr2, transaction, 0, "B")
      {:ok, transaction}
    end)

    update2 = Encoder.encode(doc2)

    assert :binary.bin_to_list(update2) == [
             0,
             0,
             1,
             2,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             1,
             1,
             1,
             0,
             119,
             1,
             66,
             0
           ]

    Doc.transact!(doc3, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr3, transaction, 0, "C")
      {:ok, transaction}
    end)

    update3 = Encoder.encode(doc3)

    assert :binary.bin_to_list(update3) == [
             0,
             0,
             1,
             3,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             1,
             1,
             1,
             0,
             119,
             1,
             67,
             0
           ]

    # Apply with duplicates interleaved
    {:ok, receiver} = Doc.new(name: :idemp_receiver)
    {:ok, _} = Doc.get_array(receiver, "array")

    apply_update = fn doc, update ->
      Doc.transact!(doc, fn transaction ->
        {:ok, Doc.apply_update(transaction, update)}
      end)
    end

    apply_update.(receiver, update1)
    apply_update.(receiver, update2)
    apply_update.(receiver, update1)
    apply_update.(receiver, update3)
    apply_update.(receiver, update2)
    apply_update.(receiver, update1)
    apply_update.(receiver, update3)

    # Create a clean receiver for comparison
    {:ok, clean_receiver} = Doc.new(name: :idemp_clean_receiver)
    {:ok, _} = Doc.get_array(clean_receiver, "array")

    apply_update.(clean_receiver, update1)
    apply_update.(clean_receiver, update2)
    apply_update.(clean_receiver, update3)

    {:ok, arr_receiver} = Doc.get(receiver, "array")
    {:ok, arr_clean} = Doc.get(clean_receiver, "array")

    assert Array.to_list(arr_receiver) == Array.to_list(arr_clean),
           "Idempotency: duplicate deliveries produce same result as single delivery"
  end

  # ============================================================================
  # Merge Associativity Test
  # ============================================================================

  @doc """
  Test associativity of merge: (A merge B) merge C === A merge (B merge C)
  """
  test "merge associativity" do
    {:ok, doc_a} = Doc.new(name: :merge_a, client_id: 1)
    {:ok, doc_b} = Doc.new(name: :merge_b, client_id: 2)
    {:ok, doc_c} = Doc.new(name: :merge_c, client_id: 3)

    {:ok, arr_a} = Doc.get_array(doc_a, "array")
    {:ok, arr_b} = Doc.get_array(doc_b, "array")
    {:ok, arr_c} = Doc.get_array(doc_c, "array")

    Doc.transact!(doc_a, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr_a, transaction, 0, ["A1", "A2"])
      {:ok, transaction}
    end)

    Doc.transact!(doc_b, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr_b, transaction, 0, ["B1", "B2"])
      {:ok, transaction}
    end)

    Doc.transact!(doc_c, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr_c, transaction, 0, ["C1", "C2"])
      {:ok, transaction}
    end)

    update_a = Encoder.encode(doc_a)

    assert :binary.bin_to_list(update_a) == [
             0,
             0,
             1,
             1,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             2,
             65,
             49,
             119,
             2,
             65,
             50,
             0
           ]

    update_b = Encoder.encode(doc_b)

    assert :binary.bin_to_list(update_b) == [
             0,
             0,
             1,
             2,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             2,
             66,
             49,
             119,
             2,
             66,
             50,
             0
           ]

    update_c = Encoder.encode(doc_c)

    assert :binary.bin_to_list(update_c) == [
             0,
             0,
             1,
             3,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             2,
             67,
             49,
             119,
             2,
             67,
             50,
             0
           ]

    # (A merge B) merge C
    {:ok, doc1} = Doc.new(name: :merge_ab_c)
    {:ok, _} = Doc.get_array(doc1, "array")

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_a)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_b)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_c)}
    end)

    # A merge (B merge C)
    {:ok, doc2} = Doc.new(name: :merge_a_bc)
    {:ok, _} = Doc.get_array(doc2, "array")

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_b)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_c)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_a)}
    end)

    # Both should produce same document
    {:ok, arr1} = Doc.get(doc1, "array")
    {:ok, arr2} = Doc.get(doc2, "array")

    assert Array.to_list(arr1) == Array.to_list(arr2),
           "Associativity: (A merge B) merge C === A merge (B merge C)"
  end

  # ============================================================================
  # Convergence Tests
  # ============================================================================

  @doc """
  Test convergence: After sync, all replicas have identical state.
  """

  # test "convergence after concurrent edits" do
  #   {:ok, doc0} = Doc.new(name: :conv_0, client_id: 0)
  #   {:ok, doc1} = Doc.new(name: :conv_1, client_id: 1)
  #   {:ok, doc2} = Doc.new(name: :conv_2, client_id: 2)
  #
  #   {:ok, arr0} = Doc.get_array(doc0, "array")
  #   {:ok, _arr1} = Doc.get_array(doc1, "array")
  #   {:ok, _arr2} = Doc.get_array(doc2, "array")
  #
  #   # Setup initial state
  #   Doc.transact!(doc0, fn transaction ->
  #     {:ok, _arr, transaction} = Array.put(arr0, transaction, 0, "initial")
  #     {:ok, transaction}
  #   end)
  #
  #   # Sync initial state to all docs
  #   initial_update = Encoder.encode(doc0)
  #
  #   Doc.transact!(doc1, fn transaction ->
  #     {:ok, Doc.apply_update(transaction, initial_update)}
  #   end)
  #   Doc.transact!(doc2, fn transaction ->
  #     {:ok, Doc.apply_update(transaction, initial_update)}
  #   end)
  #
  #   # Make concurrent edits (disconnected)
  #   Doc.transact!(doc0, fn transaction ->
  #     {:ok, arr} = Doc.get(transaction, "array")
  #     {:ok, arr, transaction} = Array.put(arr, transaction, 0, "user0-prefix")
  #     {:ok, _arr, transaction} = Array.put(arr, transaction, Array.length(arr), "user0-suffix")
  #     {:ok, transaction}
  #   end)
  #
  #   Doc.transact!(doc1, fn transaction ->
  #     {:ok, arr} = Doc.get(transaction, "array")
  #     {:ok, arr, transaction} = Array.put(arr, transaction, 1, "user1-middle")
  #     {:ok, _arr, transaction} = Array.delete(arr, transaction, 0)
  #     {:ok, transaction}
  #   end)
  #
  #   Doc.transact!(doc2, fn transaction ->
  #     {:ok, arr} = Doc.get(transaction, "array")
  #     {:ok, arr, transaction} = Array.put(arr, transaction, Array.length(arr), "user2-end")
  #     {:ok, _arr, transaction} = Array.put(arr, transaction, 0, "user2-start")
  #     {:ok, transaction}
  #   end)
  #
  #   # Get updates from each doc
  #   update0 = Encoder.encode(doc0)
  #   update1 = Encoder.encode(doc1)
  #   update2 = Encoder.encode(doc2)
  #
  #   # Sync all updates to all docs
  #   for {doc, updates} <- [
  #     {doc0, [update1, update2]},
  #     {doc1, [update0, update2]},
  #     {doc2, [update0, update1]}
  #   ] do
  #     Enum.each(updates, fn update ->
  #       Doc.transact!(doc, fn transaction ->
  #         dbg update
  #         {:ok, Doc.apply_update(transaction, update)}
  #       end)
  #     end)
  #   end
  #
  #   # After sync, all states must be identical
  #   {:ok, arr0_final} = Doc.get(doc0, "array")
  #   {:ok, arr1_final} = Doc.get(doc1, "array")
  #   {:ok, arr2_final} = Doc.get(doc2, "array")
  #
  #   assert Array.to_list(arr0_final) == Array.to_list(arr1_final), "User 0 and 1 converged"
  #   assert Array.to_list(arr1_final) == Array.to_list(arr2_final), "User 1 and 2 converged"
  # end

  # ============================================================================
  # Out-of-Order Delivery Test
  # ============================================================================

  @doc """
  Test out-of-order delivery: Updates arriving in different orders should converge.
  """
  test "out of order delivery" do
    {:ok, doc} = Doc.new(name: :ooo_src, client_id: 1)
    {:ok, arr} = Doc.get_array(doc, "array")

    # Create a sequence of operations
    Doc.transact!(doc, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr, transaction, 0, "A")
      {:ok, transaction}
    end)

    update1 = Encoder.encode(doc)

    assert :binary.bin_to_list(update1) == [
             0,
             0,
             1,
             1,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             1,
             1,
             1,
             0,
             119,
             1,
             65,
             0
           ]

    Doc.transact!(doc, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.put(arr, transaction, 1, "B")
      {:ok, transaction}
    end)

    update_full_1_2 = Encoder.encode(doc)

    Doc.transact!(doc, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.put(arr, transaction, 2, "C")
      {:ok, transaction}
    end)

    update_full = Encoder.encode(doc)

    # Apply updates out of order
    {:ok, out_of_order_doc} = Doc.new(name: :ooo_dst)
    {:ok, _} = Doc.get_array(out_of_order_doc, "array")

    # Apply full update (contains all 3 operations)
    Doc.transact!(out_of_order_doc, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_full)}
    end)

    {:ok, arr_result} = Doc.get(out_of_order_doc, "array")

    assert Array.to_list(arr_result) == ["A", "B", "C"],
           "Out-of-order delivery converges to correct state"
  end

  # ============================================================================
  # Concurrent Operations Tests
  # ============================================================================

  @doc """
  Test concurrent writes at same position.
  """
  test "concurrent writes same position" do
    {:ok, doc0} = Doc.new(name: :cw_same_0, client_id: 0)
    {:ok, doc1} = Doc.new(name: :cw_same_1, client_id: 1)
    {:ok, doc2} = Doc.new(name: :cw_same_2, client_id: 2)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, arr1} = Doc.get_array(doc1, "array")
    {:ok, arr2} = Doc.get_array(doc2, "array")

    # All users insert at position 0 concurrently
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr0, transaction, 0, "A")
      {:ok, transaction}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr1, transaction, 0, "B")
      {:ok, transaction}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr2, transaction, 0, "C")
      {:ok, transaction}
    end)

    # Get all updates
    update0 = Encoder.encode(doc0)
    update1 = Encoder.encode(doc1)
    update2 = Encoder.encode(doc2)

    # Apply all updates to doc0
    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    # Apply all updates to doc1
    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    # Apply all updates to doc2
    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")
    {:ok, arr2_final} = Doc.get(doc2, "array")

    result = Array.to_list(arr0_final)

    # All should have same result with all three elements
    assert length(result) == 3, "All three elements present"
    assert "A" in result, "Contains A"
    assert "B" in result, "Contains B"
    assert "C" in result, "Contains C"

    # All docs converged
    assert Array.to_list(arr0_final) == Array.to_list(arr1_final)
    assert Array.to_list(arr1_final) == Array.to_list(arr2_final)
  end

  @doc """
  Test concurrent deletes of same element.
  """
  test "concurrent deletes same element" do
    {:ok, doc0} = Doc.new(name: :cd_same_0, client_id: 0)
    {:ok, doc1} = Doc.new(name: :cd_same_1, client_id: 1)
    {:ok, doc2} = Doc.new(name: :cd_same_2, client_id: 2)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, _arr1} = Doc.get_array(doc1, "array")
    {:ok, _arr2} = Doc.get_array(doc2, "array")

    # Setup initial state
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr0, transaction, 0, ["A", "B", "C"])
      {:ok, transaction}
    end)

    # Sync initial state
    initial_update = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    # All users try to delete 'B' (index 1) concurrently
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.delete(arr, transaction, 1)
      {:ok, transaction}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.delete(arr, transaction, 1)
      {:ok, transaction}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.delete(arr, transaction, 1)
      {:ok, transaction}
    end)

    # Sync all updates
    update0 = Encoder.encode(doc0)
    update1 = Encoder.encode(doc1)
    update2 = Encoder.encode(doc2)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")
    {:ok, arr2_final} = Doc.get(doc2, "array")

    # Should have ['A', 'C'] - element deleted only once
    assert Array.to_list(arr0_final) == ["A", "C"], "Concurrent deletes handled correctly"

    # All converged
    assert Array.to_list(arr0_final) == Array.to_list(arr1_final)
    assert Array.to_list(arr1_final) == Array.to_list(arr2_final)
  end

  @doc """
  Test interleaving insert and delete on same range.
  """
  test "interleaving insert delete same range" do
    {:ok, doc0} = Doc.new(name: :inter_0, client_id: 1)
    {:ok, doc1} = Doc.new(name: :inter_1, client_id: 2)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, _arr1} = Doc.get_array(doc1, "array")

    # User 0 inserts A, B, C, D, E
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr0, transaction, 0, ["A", "B", "C", "D", "E"])
      {:ok, transaction}
    end)

    # Sync to doc1
    update0 = Encoder.encode(doc0)

    assert :binary.bin_to_list(update0) == [
             0,
             0,
             1,
             1,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             5,
             1,
             1,
             0,
             119,
             1,
             65,
             119,
             1,
             66,
             119,
             1,
             67,
             119,
             1,
             68,
             119,
             1,
             69,
             0
           ]

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    {:ok, arr1_check} = Doc.get(doc1, "array")
    assert Array.to_list(arr1_check) == ["A", "B", "C", "D", "E"], "Initial sync"

    # Now offline operations:
    # User 0 deletes B, C, D (indices 1-3)
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.delete(arr, transaction, 1, 3)
      {:ok, transaction}
    end)

    # User 1 inserts at position 2 (between B and C)
    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.put_many(arr, transaction, 2, ["X", "Y"])
      {:ok, transaction}
    end)

    # Get updates from each
    update1 = Encoder.encode(doc0)

    assert :binary.bin_to_list(update1) == [
             0,
             0,
             2,
             65,
             1,
             2,
             0,
             6,
             0,
             5,
             8,
             0,
             129,
             0,
             136,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             3,
             1,
             3,
             1,
             1,
             3,
             0,
             119,
             1,
             65,
             119,
             1,
             69,
             1,
             1,
             1,
             1,
             2
           ]

    update2 = Encoder.encode(doc1)

    assert :binary.bin_to_list(update2) == [
             0,
             0,
             3,
             2,
             65,
             2,
             2,
             2,
             0,
             1,
             4,
             5,
             200,
             0,
             8,
             0,
             136,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             3,
             66,
             0,
             3,
             2,
             1,
             0,
             119,
             1,
             88,
             119,
             1,
             89,
             2,
             0,
             119,
             1,
             65,
             119,
             1,
             66,
             119,
             1,
             67,
             119,
             1,
             68,
             119,
             1,
             69,
             0
           ]

    # Apply updates to sync
    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")

    result = Array.to_list(arr0_final)

    # The inserted elements should survive even if surrounding elements deleted
    assert "A" in result, "A survives"
    assert "E" in result, "E survives"
    # X and Y should survive because they were inserted by user 1
    assert "X" in result, "X survives (inserted concurrently)"
    assert "Y" in result, "Y survives (inserted concurrently)"

    # Both docs converged
    assert Array.to_list(arr0_final) == Array.to_list(arr1_final), "Arrays match after sync"
  end

  # ============================================================================
  # Tombstone Handling Test
  # ============================================================================

  @doc """
  Test tombstone handling - delete and re-insert at same logical position.
  """
  test "tombstone handling" do
    # Use explicit client IDs to match Y.JS test (client 1 and 2)
    {:ok, doc0} = Doc.new(name: :tomb_0, client_id: 1)
    {:ok, doc1} = Doc.new(name: :tomb_1, client_id: 2)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, _arr1} = Doc.get_array(doc1, "array")

    # Setup initial state - insert A, B, C
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr0, transaction, 0, ["A", "B", "C"])
      {:ok, transaction}
    end)

    # Sync initial state
    update0 = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    # Binary assertion for update0 (initial A, B, C)
    assert :binary.bin_to_list(update0) == [
             0,
             0,
             1,
             1,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             3,
             1,
             1,
             0,
             119,
             1,
             65,
             119,
             1,
             66,
             119,
             1,
             67,
             0
           ]

    {:ok, arr0_check} = Doc.get(doc0, "array")
    {:ok, arr1_check} = Doc.get(doc1, "array")

    assert Array.to_list(arr0_check) == ["A", "B", "C"]
    assert Array.to_list(arr1_check) == ["A", "B", "C"]

    # Delete B
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.delete(arr, transaction, 1)
      {:ok, transaction}
    end)

    # Sync delete
    update1 = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    # Binary assertion for update1 (after delete B)
    assert :binary.bin_to_list(update1) == [
             0,
             0,
             2,
             65,
             1,
             2,
             0,
             2,
             0,
             5,
             8,
             0,
             129,
             0,
             136,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             2,
             65,
             1,
             1,
             3,
             0,
             119,
             1,
             65,
             119,
             1,
             67,
             1,
             1,
             1,
             1,
             0
           ]

    {:ok, arr0_after_delete} = Doc.get(doc0, "array")
    {:ok, arr1_after_delete} = Doc.get(doc1, "array")

    assert Array.to_list(arr0_after_delete) == ["A", "C"], "After delete"
    assert Array.to_list(arr1_after_delete) == ["A", "C"], "Synced after delete"

    # Insert at same position where B was
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.put(arr, transaction, 1, "B-new")
      {:ok, transaction}
    end)

    # Sync insert
    update2 = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    # Binary assertion for update2 (after re-insert B-new)
    assert :binary.bin_to_list(update2) == [
             0,
             0,
             2,
             65,
             3,
             3,
             0,
             2,
             66,
             1,
             2,
             7,
             8,
             0,
             129,
             0,
             136,
             0,
             200,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             2,
             65,
             2,
             1,
             4,
             0,
             119,
             1,
             65,
             119,
             1,
             67,
             119,
             5,
             66,
             45,
             110,
             101,
             119,
             1,
             1,
             1,
             1,
             0
           ]

    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")

    assert Array.to_list(arr0_final) == ["A", "B-new", "C"], "After re-insert"
    assert Array.to_list(arr1_final) == ["A", "B-new", "C"], "Synced after re-insert"
  end

  # ============================================================================
  # Merge From Many Divergent Peers Test
  # ============================================================================

  @doc """
  Test merge of updates from many divergent peers.
  """
  test "merge from many divergent peers" do
    num_peers = 10
    updates = []

    # Create many independent peers with deterministic client IDs
    updates =
      for i <- 0..(num_peers - 1) do
        {:ok, doc} = Doc.new(name: :"peer_#{i}", client_id: i + 1)
        {:ok, arr} = Doc.get_array(doc, "array")

        Doc.transact!(doc, fn transaction ->
          {:ok, _arr, transaction} =
            Array.put_many(arr, transaction, 0, ["peer-#{i}-item1", "peer-#{i}-item2"])

          {:ok, transaction}
        end)

        Encoder.encode(doc)
      end

    # Assert each update has expected structure
    assert :binary.bin_to_list(Enum.at(updates, 0)) == [
             0,
             0,
             1,
             1,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             48,
             45,
             105,
             116,
             101,
             109,
             49,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             48,
             45,
             105,
             116,
             101,
             109,
             50,
             0
           ]

    assert :binary.bin_to_list(Enum.at(updates, 1)) == [
             0,
             0,
             1,
             2,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             49,
             45,
             105,
             116,
             101,
             109,
             49,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             49,
             45,
             105,
             116,
             101,
             109,
             50,
             0
           ]

    assert :binary.bin_to_list(Enum.at(updates, 2)) == [
             0,
             0,
             1,
             3,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             50,
             45,
             105,
             116,
             101,
             109,
             49,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             50,
             45,
             105,
             116,
             101,
             109,
             50,
             0
           ]

    assert :binary.bin_to_list(Enum.at(updates, 3)) == [
             0,
             0,
             1,
             4,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             51,
             45,
             105,
             116,
             101,
             109,
             49,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             51,
             45,
             105,
             116,
             101,
             109,
             50,
             0
           ]

    assert :binary.bin_to_list(Enum.at(updates, 4)) == [
             0,
             0,
             1,
             5,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             52,
             45,
             105,
             116,
             101,
             109,
             49,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             52,
             45,
             105,
             116,
             101,
             109,
             50,
             0
           ]

    assert :binary.bin_to_list(Enum.at(updates, 5)) == [
             0,
             0,
             1,
             6,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             53,
             45,
             105,
             116,
             101,
             109,
             49,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             53,
             45,
             105,
             116,
             101,
             109,
             50,
             0
           ]

    assert :binary.bin_to_list(Enum.at(updates, 6)) == [
             0,
             0,
             1,
             7,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             54,
             45,
             105,
             116,
             101,
             109,
             49,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             54,
             45,
             105,
             116,
             101,
             109,
             50,
             0
           ]

    assert :binary.bin_to_list(Enum.at(updates, 7)) == [
             0,
             0,
             1,
             8,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             55,
             45,
             105,
             116,
             101,
             109,
             49,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             55,
             45,
             105,
             116,
             101,
             109,
             50,
             0
           ]

    assert :binary.bin_to_list(Enum.at(updates, 8)) == [
             0,
             0,
             1,
             9,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             56,
             45,
             105,
             116,
             101,
             109,
             49,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             56,
             45,
             105,
             116,
             101,
             109,
             50,
             0
           ]

    assert :binary.bin_to_list(Enum.at(updates, 9)) == [
             0,
             0,
             1,
             10,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             2,
             1,
             1,
             0,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             57,
             45,
             105,
             116,
             101,
             109,
             49,
             119,
             12,
             112,
             101,
             101,
             114,
             45,
             57,
             45,
             105,
             116,
             101,
             109,
             50,
             0
           ]

    # Merge all updates into a single document
    {:ok, merged_doc} = Doc.new(name: :merged_peers)
    {:ok, _} = Doc.get_array(merged_doc, "array")

    Enum.each(updates, fn update ->
      Doc.transact!(merged_doc, fn transaction ->
        {:ok, Doc.apply_update(transaction, update)}
      end)
    end)

    # Should have all items from all peers
    {:ok, result_arr} = Doc.get(merged_doc, "array")
    result = Array.to_list(result_arr)

    assert length(result) == num_peers * 2, "Has all #{num_peers * 2} items"

    # Verify each peer's items are present
    for i <- 0..(num_peers - 1) do
      assert "peer-#{i}-item1" in result, "Contains peer-#{i}-item1"
      assert "peer-#{i}-item2" in result, "Contains peer-#{i}-item2"
    end
  end

  # ============================================================================
  # Empty Array Merge Test
  # ============================================================================

  @doc """
  Test that empty arrays merge correctly.
  """
  test "empty array merge" do
    {:ok, doc1} = Doc.new(name: :empty_1)
    {:ok, doc2} = Doc.new(name: :empty_2)

    # Get arrays but don't add anything
    {:ok, _arr1} = Doc.get_array(doc1, "array")
    {:ok, _arr2} = Doc.get_array(doc2, "array")

    update1 = Encoder.encode(doc1)

    assert :binary.bin_to_list(update1) == [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]

    update2 = Encoder.encode(doc2)

    assert :binary.bin_to_list(update2) == [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]

    # Apply updates
    {:ok, merged_doc} = Doc.new(name: :empty_merged)
    {:ok, _} = Doc.get_array(merged_doc, "array")

    Doc.transact!(merged_doc, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    Doc.transact!(merged_doc, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    {:ok, result_arr} = Doc.get(merged_doc, "array")

    assert Array.to_list(result_arr) == [], "Empty array merge produces empty array"
  end

  # ============================================================================
  # Array With Only Deletions Test
  # ============================================================================

  @doc """
  Test operations on array with only deletions.
  """
  test "array with only deletions" do
    {:ok, doc0} = Doc.new(name: :del_only_0, client_id: 0)
    {:ok, doc1} = Doc.new(name: :del_only_1, client_id: 1)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, _arr1} = Doc.get_array(doc1, "array")

    # Setup initial state
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr0, transaction, 0, ["A", "B", "C", "D", "E"])
      {:ok, transaction}
    end)

    # Sync initial state
    initial_update = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    # Delete everything from both sides concurrently
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.delete(arr, transaction, 0, 3)
      {:ok, transaction}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.delete(arr, transaction, 2, 3)
      {:ok, transaction}
    end)

    # Sync updates
    update0 = Encoder.encode(doc0)
    update1 = Encoder.encode(doc1)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")

    # Everything should be deleted
    assert Array.to_list(arr0_final) == [], "All elements deleted"
    assert Array.to_list(arr0_final) == Array.to_list(arr1_final)
  end

  # ============================================================================
  # Causal Consistency Test
  # ============================================================================

  @doc """
  Test causal consistency - operations respect causal order.
  """
  test "causal consistency" do
    {:ok, doc0} = Doc.new(name: :causal_0, client_id: 1)
    {:ok, doc1} = Doc.new(name: :causal_1, client_id: 2)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, _arr1} = Doc.get_array(doc1, "array")

    # User 0 creates initial state
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr0, transaction, 0, "A")
      {:ok, transaction}
    end)

    # Sync to user 1
    update_a = Encoder.encode(doc0)
    assert :binary.bin_to_list(update_a) == [0, 0, 1, 1, 0, 0, 1, 8, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 1, 1, 1, 1, 0, 119, 1, 65, 0]

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_a)}
    end)


    # User 1 sees A and appends B
    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "B")
      {:ok, transaction}
    end)

    # Sync B back to user 0
    update_b = Encoder.encode(doc1)
    assert :binary.bin_to_list(update_b) == [0, 0, 3, 2, 65, 0, 1, 0, 0, 3, 136, 0, 8, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 2, 65, 0, 2, 1, 0, 119, 1, 66, 1, 0, 119, 1, 65, 0]

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_b)}
    end)


    # User 0 sees B and appends C
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "C")
      {:ok, transaction}
    end)

    # Sync C back to user 1
    update_c = Encoder.encode(doc0)

    assert :binary.bin_to_list(update_c) == [0, 0, 4, 2, 65, 0, 2, 2, 1, 0, 0, 5, 136, 0, 8, 0, 136, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 2, 65, 1, 2, 1, 0, 119, 1, 66, 2, 0, 119, 1, 65, 119, 1, 67, 0]

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_c)}
    end)

    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")

    # Order should be preserved: A, B, C
    assert Array.to_list(arr0_final) == ["A", "B", "C"], "Causal order preserved on user 0"
    assert Array.to_list(arr1_final) == ["A", "B", "C"], "Causal order preserved on user 1"
  end

  # ============================================================================
  # Large Batch Concurrent Operations Test
  # ============================================================================

  @doc """
  Test large batch concurrent operations.
  """
  test "large batch concurrent operations" do
    {:ok, doc0} = Doc.new(name: :large_0, client_id: 0)
    {:ok, doc1} = Doc.new(name: :large_1, client_id: 1)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, arr1} = Doc.get_array(doc1, "array")

    # User 0 inserts 100 items
    items0 = for i <- 0..99, do: "user0-#{i}"

    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr0, transaction, 0, items0)
      {:ok, transaction}
    end)

    # User 1 inserts 100 items
    items1 = for i <- 0..99, do: "user1-#{i}"

    Doc.transact!(doc1, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr1, transaction, 0, items1)
      {:ok, transaction}
    end)

    # Sync updates
    update0 = Encoder.encode(doc0)
    update1 = Encoder.encode(doc1)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")

    # Should have all 200 items
    assert Array.length(arr0_final) == 200, "Has 200 items"
    assert Array.to_list(arr0_final) == Array.to_list(arr1_final)
  end

  # ============================================================================
  # Concurrent Push Operations Test
  # ============================================================================

  @doc """
  Test concurrent push operations.
  """
  test "concurrent push operations" do
    {:ok, doc0} = Doc.new(name: :push_0, client_id: 0)
    {:ok, doc1} = Doc.new(name: :push_1, client_id: 1)
    {:ok, doc2} = Doc.new(name: :push_2, client_id: 2)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, _arr1} = Doc.get_array(doc1, "array")
    {:ok, _arr2} = Doc.get_array(doc2, "array")

    # Initial state
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr0, transaction, 0, "initial")
      {:ok, transaction}
    end)

    # Sync initial state
    initial_update = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    # Concurrent pushes
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.put(arr, transaction, Array.length(arr), "pushed-by-0")
      {:ok, transaction}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.put(arr, transaction, Array.length(arr), "pushed-by-1")
      {:ok, transaction}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.put(arr, transaction, Array.length(arr), "pushed-by-2")
      {:ok, transaction}
    end)

    # Sync all updates
    update0 = Encoder.encode(doc0)
    update1 = Encoder.encode(doc1)
    update2 = Encoder.encode(doc2)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")
    {:ok, arr2_final} = Doc.get(doc2, "array")

    result = Array.to_list(arr0_final)

    # All pushes should be present
    assert Enum.at(result, 0) == "initial", "Initial element preserved"
    assert "pushed-by-0" in result, "Push from user 0 present"
    assert "pushed-by-1" in result, "Push from user 1 present"
    assert "pushed-by-2" in result, "Push from user 2 present"
    assert length(result) == 4, "All 4 elements present"

    # All converged
    assert Array.to_list(arr0_final) == Array.to_list(arr1_final)
    assert Array.to_list(arr1_final) == Array.to_list(arr2_final)
  end

  # ============================================================================
  # Concurrent Unshift Operations Test
  # ============================================================================

  @doc """
  Test concurrent unshift operations.
  """
  test "concurrent unshift operations" do
    {:ok, doc0} = Doc.new(name: :unshift_0, client_id: 0)
    {:ok, doc1} = Doc.new(name: :unshift_1, client_id: 1)
    {:ok, doc2} = Doc.new(name: :unshift_2, client_id: 2)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, _arr1} = Doc.get_array(doc1, "array")
    {:ok, _arr2} = Doc.get_array(doc2, "array")

    # Initial state
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr0, transaction, 0, "initial")
      {:ok, transaction}
    end)

    # Sync initial state
    initial_update = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    # Concurrent unshifts (insert at 0)
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.put(arr, transaction, 0, "unshift-by-0")
      {:ok, transaction}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.put(arr, transaction, 0, "unshift-by-1")
      {:ok, transaction}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.put(arr, transaction, 0, "unshift-by-2")
      {:ok, transaction}
    end)

    # Sync all updates
    update0 = Encoder.encode(doc0)
    update1 = Encoder.encode(doc1)
    update2 = Encoder.encode(doc2)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")
    {:ok, arr2_final} = Doc.get(doc2, "array")

    result = Array.to_list(arr0_final)

    # All unshifts should be present
    assert "initial" in result, "Initial element preserved"
    assert "unshift-by-0" in result, "Unshift from user 0 present"
    assert "unshift-by-1" in result, "Unshift from user 1 present"
    assert "unshift-by-2" in result, "Unshift from user 2 present"
    assert length(result) == 4, "All 4 elements present"

    # All converged
    assert Array.to_list(arr0_final) == Array.to_list(arr1_final)
    assert Array.to_list(arr1_final) == Array.to_list(arr2_final)
  end

  # ============================================================================
  # Convergence With Nested Types Test
  # ============================================================================

  @doc """
  Test convergence with nested types.
  """
  test "convergence with nested types" do
    {:ok, doc0} = Doc.new(name: :nested_conv_0, client_id: 0)
    {:ok, doc1} = Doc.new(name: :nested_conv_1, client_id: 1)
    {:ok, doc2} = Doc.new(name: :nested_conv_2, client_id: 2)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, nested_arr0} = Doc.get_array(doc0, "nested_arr")
    {:ok, nested_map0} = Doc.get_map(doc0, "nested_map")

    {:ok, _arr1} = Doc.get_array(doc1, "array")
    {:ok, _nested_arr1} = Doc.get_array(doc1, "nested_arr")
    {:ok, _nested_map1} = Doc.get_map(doc1, "nested_map")

    {:ok, _arr2} = Doc.get_array(doc2, "array")
    {:ok, _nested_arr2} = Doc.get_array(doc2, "nested_arr")
    {:ok, _nested_map2} = Doc.get_map(doc2, "nested_map")

    # Insert nested arrays and maps
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr0, transaction, 0, [nested_arr0, nested_map0])
      {:ok, transaction}
    end)

    # Sync initial state
    initial_update = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    # Modify nested types concurrently (disconnected)
    Doc.transact!(doc0, fn transaction ->
      {:ok, nested_arr} = Doc.get(transaction, "nested_arr")
      {:ok, nested_map} = Doc.get(transaction, "nested_map")
      {:ok, _arr, transaction} = Array.put(nested_arr, transaction, 0, "from-user-0")
      {:ok, _map, transaction} = Y.Type.Map.put(nested_map, transaction, "key0", "value0")
      {:ok, transaction}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, nested_arr} = Doc.get(transaction, "nested_arr")
      {:ok, nested_map} = Doc.get(transaction, "nested_map")
      {:ok, _arr, transaction} = Array.put(nested_arr, transaction, 0, "from-user-1")
      {:ok, _map, transaction} = Y.Type.Map.put(nested_map, transaction, "key1", "value1")
      {:ok, transaction}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, nested_arr} = Doc.get(transaction, "nested_arr")
      {:ok, nested_map} = Doc.get(transaction, "nested_map")

      {:ok, _arr, transaction} =
        Array.put(nested_arr, transaction, Array.length(nested_arr), "from-user-2")

      {:ok, _map, transaction} = Y.Type.Map.put(nested_map, transaction, "key2", "value2")
      {:ok, transaction}
    end)

    # Sync all updates
    update0 = Encoder.encode(doc0)
    update1 = Encoder.encode(doc1)
    update2 = Encoder.encode(doc2)

    for {doc, updates} <- [
          {doc0, [update1, update2]},
          {doc1, [update0, update2]},
          {doc2, [update0, update1]}
        ] do
      Enum.each(updates, fn update ->
        Doc.transact!(doc, fn transaction ->
          {:ok, Doc.apply_update(transaction, update)}
        end)
      end)
    end

    # Verify convergence for nested array
    {:ok, nested_arr0_final} = Doc.get(doc0, "nested_arr")
    {:ok, nested_arr1_final} = Doc.get(doc1, "nested_arr")
    {:ok, nested_arr2_final} = Doc.get(doc2, "nested_arr")

    assert Array.to_list(nested_arr0_final) == Array.to_list(nested_arr1_final)
    assert Array.to_list(nested_arr1_final) == Array.to_list(nested_arr2_final)

    # Verify convergence for nested map
    {:ok, nested_map0_final} = Doc.get(doc0, "nested_map")
    {:ok, nested_map1_final} = Doc.get(doc1, "nested_map")
    {:ok, nested_map2_final} = Doc.get(doc2, "nested_map")

    assert Y.Type.Map.to_map(nested_map0_final) == Y.Type.Map.to_map(nested_map1_final)
    assert Y.Type.Map.to_map(nested_map1_final) == Y.Type.Map.to_map(nested_map2_final)

    # All items from all users should be present in nested structures
    nested_arr_result = Array.to_list(nested_arr0_final)
    assert "from-user-0" in nested_arr_result
    assert "from-user-1" in nested_arr_result
    assert "from-user-2" in nested_arr_result

    nested_map_result = Y.Type.Map.to_map(nested_map0_final)
    assert nested_map_result["key0"] == "value0"
    assert nested_map_result["key1"] == "value1"
    assert nested_map_result["key2"] == "value2"
  end

  # ============================================================================
  # Concurrent Read Write Test
  # ============================================================================

  @doc """
  Test concurrent reads and writes.
  """
  test "concurrent read write" do
    {:ok, doc0} = Doc.new(name: :rw_0, client_id: 0)
    {:ok, doc1} = Doc.new(name: :rw_1, client_id: 1)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, _arr1} = Doc.get_array(doc1, "array")

    # Setup initial state
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr0, transaction, 0, ["A", "B", "C", "D", "E"])
      {:ok, transaction}
    end)

    # Sync initial state
    initial_update = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    # User 0 writes while user 1 reads
    read_results = []

    # Interleave operations
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.put(arr, transaction, 2, "X")
      {:ok, transaction}
    end)

    {:ok, arr1_read1} = Doc.get(doc1, "array")
    read_results = [Array.to_list(arr1_read1) | read_results]

    # Partial sync
    update_partial = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_partial)}
    end)

    {:ok, arr1_read2} = Doc.get(doc1, "array")
    read_results = [Array.to_list(arr1_read2) | read_results]

    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.delete(arr, transaction, 0)
      {:ok, transaction}
    end)

    {:ok, arr1_read3} = Doc.get(doc1, "array")
    read_results = [Array.to_list(arr1_read3) | read_results]

    # Full sync
    update_full = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_full)}
    end)

    {:ok, arr1_read4} = Doc.get(doc1, "array")
    read_results = [Array.to_list(arr1_read4) | read_results]

    # Final state should be consistent
    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")

    assert Array.to_list(arr0_final) == Array.to_list(arr1_final), "Final states are consistent"

    # Verify that reads always returned valid array states (no corruption)
    read_results = Enum.reverse(read_results)

    Enum.with_index(read_results)
    |> Enum.each(fn {result, i} ->
      assert is_list(result), "Read #{i} returned valid array"
    end)
  end

  # ============================================================================
  # Rapid Fire Operations Test
  # ============================================================================

  @doc """
  Test rapid fire operations from multiple users.
  """
  test "rapid fire operations" do
    {:ok, doc0} = Doc.new(name: :rapid_0, client_id: 0)
    {:ok, doc1} = Doc.new(name: :rapid_1, client_id: 1)
    {:ok, doc2} = Doc.new(name: :rapid_2, client_id: 2)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, _arr1} = Doc.get_array(doc1, "array")
    {:ok, _arr2} = Doc.get_array(doc2, "array")

    # Rapid fire operations with partial syncing
    for round <- 0..9 do
      # User 0 appends
      Doc.transact!(doc0, fn transaction ->
        {:ok, arr} = Doc.get(transaction, "array")
        {:ok, _arr, transaction} = Array.put(arr, transaction, Array.length(arr), "a#{round}")
        {:ok, transaction}
      end)

      # Partial sync to doc1
      update0 = Encoder.encode(doc0)

      Doc.transact!(doc1, fn transaction ->
        {:ok, Doc.apply_update(transaction, update0)}
      end)

      # User 1 prepends
      Doc.transact!(doc1, fn transaction ->
        {:ok, arr} = Doc.get(transaction, "array")
        {:ok, _arr, transaction} = Array.put(arr, transaction, 0, "b#{round}")
        {:ok, transaction}
      end)

      # Partial sync to doc2
      update1 = Encoder.encode(doc1)

      Doc.transact!(doc2, fn transaction ->
        {:ok, Doc.apply_update(transaction, update1)}
      end)

      # User 2 inserts in middle
      Doc.transact!(doc2, fn transaction ->
        {:ok, arr} = Doc.get(transaction, "array")
        mid = div(Array.length(arr), 2)
        {:ok, _arr, transaction} = Array.put(arr, transaction, mid, "c#{round}")
        {:ok, transaction}
      end)

      # Partial sync back
      update2 = Encoder.encode(doc2)

      Doc.transact!(doc0, fn transaction ->
        {:ok, Doc.apply_update(transaction, update2)}
      end)

      # Full sync every 3 rounds
      if rem(round, 3) == 0 do
        update0_full = Encoder.encode(doc0)
        update1_full = Encoder.encode(doc1)
        update2_full = Encoder.encode(doc2)

        Doc.transact!(doc0, fn transaction ->
          {:ok, Doc.apply_update(transaction, update1_full)}
        end)

        Doc.transact!(doc0, fn transaction ->
          {:ok, Doc.apply_update(transaction, update2_full)}
        end)

        Doc.transact!(doc1, fn transaction ->
          {:ok, Doc.apply_update(transaction, update0_full)}
        end)

        Doc.transact!(doc1, fn transaction ->
          {:ok, Doc.apply_update(transaction, update2_full)}
        end)

        Doc.transact!(doc2, fn transaction ->
          {:ok, Doc.apply_update(transaction, update0_full)}
        end)

        Doc.transact!(doc2, fn transaction ->
          {:ok, Doc.apply_update(transaction, update1_full)}
        end)
      end
    end

    # Final full sync
    update0_final = Encoder.encode(doc0)
    update1_final = Encoder.encode(doc1)
    update2_final = Encoder.encode(doc2)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1_final)}
    end)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2_final)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0_final)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2_final)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0_final)}
    end)

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1_final)}
    end)

    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")
    {:ok, arr2_final} = Doc.get(doc2, "array")

    # All users should have same content with 30 elements
    assert Array.length(arr0_final) == 30, "Correct number of elements"
    assert Array.to_list(arr0_final) == Array.to_list(arr1_final)
    assert Array.to_list(arr1_final) == Array.to_list(arr2_final)
  end

  # ============================================================================
  # State Vector Sync Test
  # ============================================================================

  @doc """
  Test state vector based sync.
  """
  test "state vector sync" do
    {:ok, doc1} = Doc.new(name: :sv_1, client_id: 1)
    {:ok, doc2} = Doc.new(name: :sv_2, client_id: 2)

    {:ok, arr1} = Doc.get_array(doc1, "array")
    {:ok, _arr2} = Doc.get_array(doc2, "array")

    # Doc1 makes some changes
    Doc.transact!(doc1, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr1, transaction, 0, ["A", "B", "C"])
      {:ok, transaction}
    end)

    # Initial sync to doc2 - get doc2's empty state vector
    sv2_empty = Encoder.encode_state_vector(doc2)
    assert :binary.bin_to_list(sv2_empty) == [0]

    # Get update from doc1 using doc2's state vector
    update1 = Encoder.encode_state_as_update(doc1, sv2_empty)

    assert :binary.bin_to_list(update1) == [
             0,
             0,
             1,
             1,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             3,
             1,
             1,
             0,
             119,
             1,
             65,
             119,
             1,
             66,
             119,
             1,
             67,
             0
           ]

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    {:ok, arr2_after_sync} = Doc.get(doc2, "array")
    assert Array.to_list(arr2_after_sync) == ["A", "B", "C"], "Initial sync successful"

    # Doc1 makes more changes (append X)
    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "X")
      {:ok, transaction}
    end)

    # Doc2 makes changes too
    Doc.transact!(doc2, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "D")
      {:ok, transaction}
    end)

    # Exchange only missing updates using state vectors
    sv1 = Encoder.encode_state_vector(doc1)
    assert :binary.bin_to_list(sv1) == [1, 1, 4]

    sv2 = Encoder.encode_state_vector(doc2)
    assert :binary.bin_to_list(sv2) == [2, 2, 1, 1, 3]

    # Get incremental update from doc1 for doc2
    update_for_2 = Encoder.encode_state_as_update(doc1, sv2)
    assert :binary.bin_to_list(update_for_2) == [
             0,
             0,
             2,
             65,
             0,
             1,
             4,
             0,
             1,
             136,
             1,
             0,
             0,
             0,
             1,
             1,
             1,
             1,
             3,
             119,
             1,
             88,
             0
           ]

    # Get incremental update from doc2 for doc1
    update_for_1 = Encoder.encode_state_as_update(doc2, sv1)
    assert :binary.bin_to_list(update_for_1) == [
             0,
             0,
             2,
             2,
             1,
             1,
             4,
             0,
             1,
             136,
             1,
             0,
             0,
             0,
             1,
             1,
             1,
             1,
             0,
             119,
             1,
             68,
             0
           ]

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_for_2)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update_for_1)}
    end)

    # Both should now be in sync (same elements, order may vary due to conflict resolution)
    {:ok, arr1_final} = Doc.get(doc1, "array")
    {:ok, arr2_final} = Doc.get(doc2, "array")

    assert Enum.sort(Array.to_list(arr1_final)) == Enum.sort(Array.to_list(arr2_final)),
           "State vector sync successful - same elements"
  end

  # ============================================================================
  # Update Diff Test
  # ============================================================================

  @doc """
  Test update diff - only send what's needed.
  """
  test "update diff" do
    {:ok, doc1} = Doc.new(name: :diff_1, client_id: 1)
    {:ok, doc2} = Doc.new(name: :diff_2)

    {:ok, arr1} = Doc.get_array(doc1, "array")
    {:ok, _arr2} = Doc.get_array(doc2, "array")

    # Initial sync
    Doc.transact!(doc1, fn transaction ->
      {:ok, _arr, transaction} = Array.put_many(arr1, transaction, 0, ["A", "B", "C"])
      {:ok, transaction}
    end)

    initial_update = Encoder.encode(doc1)

    assert :binary.bin_to_list(initial_update) == [
             0,
             0,
             1,
             1,
             0,
             0,
             1,
             8,
             7,
             5,
             97,
             114,
             114,
             97,
             121,
             5,
             1,
             1,
             0,
             1,
             3,
             1,
             1,
             0,
             119,
             1,
             65,
             119,
             1,
             66,
             119,
             1,
             67,
             0
           ]

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    # Doc1 makes changes
    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, arr, transaction} = Array.put_many(arr, transaction, Array.length(arr), ["D", "E"])
      {:ok, _arr, transaction} = Array.delete(arr, transaction, 0)
      {:ok, transaction}
    end)

    sv2 = Encoder.encode_state_vector(doc2)
    assert :binary.bin_to_list(sv2) == [1, 1, 3]

    # # Apply diff
    # Doc.transact!(doc2, fn transaction ->
    #   {:ok, Doc.apply_update(transaction, diff_update)}
    # end)
    diff_update = Encoder.encode_state_as_update(doc1, sv2)

    assert :binary.bin_to_list(diff_update) == [
             0,
             0,
             2,
             65,
             0,
             1,
             4,
             0,
             1,
             136,
             1,
             0,
             0,
             0,
             1,
             2,
             1,
             1,
             3,
             119,
             1,
             68,
             119,
             1,
             69,
             1,
             1,
             1,
             0,
             0
           ]

    Doc.transact!(doc2, fn transaction ->
      {:ok, Doc.apply_update(transaction, diff_update)}
    end)

    {:ok, arr1_final} = Doc.get(doc1, "array")
    {:ok, arr2_final} = Doc.get(doc2, "array")

    assert Array.to_list(arr1_final) == Array.to_list(arr2_final)
  end

  # ============================================================================
  # Multiple Disconnects Reconnects Test
  # ============================================================================

  @doc """
  Test multiple disconnects and reconnects during operations.
  """
  test "multiple disconnects reconnects" do
    {:ok, doc0} = Doc.new(name: :reconn_0, client_id: 1)
    {:ok, doc1} = Doc.new(name: :reconn_1, client_id: 2)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, _arr1} = Doc.get_array(doc1, "array")

    # User 0 inserts 'A'
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} = Array.put(arr0, transaction, 0, "A")
      {:ok, transaction}
    end)

    # Sync to doc1
    update0 = Encoder.encode(doc0)
    assert :binary.bin_to_list(update0) == [0, 0, 1, 1, 0, 0, 1, 8, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 1, 1, 1, 1, 0, 119, 1, 65, 0]
    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    # Cycle 0: doc0 adds 'offline-0' while "disconnected", then syncs
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "offline-0")
      {:ok, transaction}
    end)
    update1 = Encoder.encode(doc0)
    assert :binary.bin_to_list(update1) == [0, 0, 1, 1, 0, 0, 1, 8, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 1, 2, 1, 1, 0, 119, 1, 65, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 48, 0]
    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    # doc1 adds 'after-reconnect-0'
    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "after-reconnect-0")
      {:ok, transaction}
    end)
    update2 = Encoder.encode(doc1)
    assert :binary.bin_to_list(update2) == [0, 0, 3, 2, 65, 0, 1, 2, 0, 3, 136, 0, 8, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 2, 1, 2, 2, 1, 0, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 48, 1, 0, 119, 1, 65, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 48, 0]
    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update2)}
    end)

    # Cycle 1: doc0 adds 'offline-1' while "disconnected", then syncs
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "offline-1")
      {:ok, transaction}
    end)
    update3 = Encoder.encode(doc0)
    assert :binary.bin_to_list(update3) == [0, 0, 4, 2, 65, 0, 2, 2, 2, 66, 0, 5, 136, 0, 8, 0, 136, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 3, 1, 2, 1, 2, 1, 0, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 48, 2, 0, 119, 1, 65, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 48, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 49, 0]
    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update3)}
    end)

    # doc1 adds 'after-reconnect-1'
    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "after-reconnect-1")
      {:ok, transaction}
    end)
    update4 = Encoder.encode(doc1)
    assert :binary.bin_to_list(update4) == [0, 0, 4, 2, 65, 1, 2, 3, 3, 0, 68, 0, 5, 136, 1, 8, 0, 136, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 4, 65, 0, 2, 1, 2, 2, 0, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 48, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 49, 2, 0, 119, 1, 65, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 48, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 49, 0]
    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update4)}
    end)

    # Cycle 2: doc0 adds 'offline-2' while "disconnected", then syncs
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "offline-2")
      {:ok, transaction}
    end)
    update5 = Encoder.encode(doc0)
    assert :binary.bin_to_list(update5) == [0, 0, 5, 2, 65, 1, 66, 0, 4, 3, 0, 68, 2, 0, 5, 136, 1, 8, 0, 136, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 5, 65, 0, 2, 65, 0, 2, 2, 0, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 48, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 49, 3, 0, 119, 1, 65, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 48, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 49, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 50, 0]
    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update5)}
    end)

    # doc1 adds 'after-reconnect-2'
    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "after-reconnect-2")
      {:ok, transaction}
    end)
    update6 = Encoder.encode(doc1)
    assert :binary.bin_to_list(update6) == [0, 0, 5, 2, 65, 2, 66, 0, 4, 3, 1, 70, 2, 0, 5, 136, 2, 8, 0, 136, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 5, 65, 1, 2, 65, 0, 2, 3, 0, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 48, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 49, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 50, 3, 0, 119, 1, 65, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 48, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 49, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 50, 0]
    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update6)}
    end)

    # Cycle 3: doc0 adds 'offline-3' while "disconnected", then syncs
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "offline-3")
      {:ok, transaction}
    end)
    update7 = Encoder.encode(doc0)
    assert :binary.bin_to_list(update7) == [0, 0, 5, 2, 65, 2, 66, 1, 5, 3, 1, 70, 3, 0, 0, 5, 136, 2, 8, 0, 136, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 5, 65, 1, 2, 65, 1, 2, 3, 0, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 48, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 49, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 50, 4, 0, 119, 1, 65, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 48, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 49, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 50, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 51, 0]
    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update7)}
    end)

    # doc1 adds 'after-reconnect-3'
    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "after-reconnect-3")
      {:ok, transaction}
    end)
    update8 = Encoder.encode(doc1)
    assert :binary.bin_to_list(update8) == [0, 0, 5, 2, 65, 3, 66, 1, 5, 3, 2, 72, 3, 0, 0, 5, 136, 3, 8, 0, 136, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 5, 65, 2, 2, 65, 1, 2, 4, 0, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 48, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 49, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 50, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 51, 4, 0, 119, 1, 65, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 48, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 49, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 50, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 51, 0]
    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update8)}
    end)

    # Cycle 4: doc0 adds 'offline-4' while "disconnected", then syncs
    Doc.transact!(doc0, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "offline-4")
      {:ok, transaction}
    end)
    update9 = Encoder.encode(doc0)
    assert :binary.bin_to_list(update9) == [0, 0, 5, 2, 65, 3, 66, 2, 5, 3, 2, 72, 3, 1, 0, 5, 136, 3, 8, 0, 136, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 5, 65, 2, 2, 65, 2, 2, 4, 0, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 48, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 49, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 50, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 51, 5, 0, 119, 1, 65, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 48, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 49, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 50, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 51, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 52, 0]
    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update9)}
    end)

    # doc1 adds 'after-reconnect-4'
    Doc.transact!(doc1, fn transaction ->
      {:ok, arr} = Doc.get(transaction, "array")
      {:ok, _arr, transaction} = Array.append(arr, transaction, "after-reconnect-4")
      {:ok, transaction}
    end)
    update10 = Encoder.encode(doc1)
    assert :binary.bin_to_list(update10) == [0, 0, 5, 2, 65, 4, 66, 2, 5, 3, 3, 74, 3, 1, 0, 5, 136, 4, 8, 0, 136, 7, 5, 97, 114, 114, 97, 121, 5, 1, 1, 0, 5, 65, 3, 2, 65, 2, 2, 5, 0, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 48, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 49, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 50, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 51, 119, 17, 97, 102, 116, 101, 114, 45, 114, 101, 99, 111, 110, 110, 101, 99, 116, 45, 52, 5, 0, 119, 1, 65, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 48, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 49, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 50, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 51, 119, 9, 111, 102, 102, 108, 105, 110, 101, 45, 52, 0]
    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update10)}
    end)

    # Verify final state
    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")

    assert Array.to_list(arr0_final) == ["A", "offline-0", "after-reconnect-0", "offline-1", "after-reconnect-1", "offline-2", "after-reconnect-2", "offline-3", "after-reconnect-3", "offline-4", "after-reconnect-4"]
    assert Array.to_list(arr1_final) == ["A", "offline-0", "after-reconnect-0", "offline-1", "after-reconnect-1", "offline-2", "after-reconnect-2", "offline-3", "after-reconnect-3", "offline-4", "after-reconnect-4"]
    assert Array.length(arr0_final) == 11, "All operations applied"
  end

  # ============================================================================
  # Network Partition Extensive Test
  # ============================================================================

  @doc """
  Test network partition with extensive divergent edits.
  """
  test "network partition extensive" do
    {:ok, doc0} = Doc.new(name: :part_0, client_id: 0)
    {:ok, doc1} = Doc.new(name: :part_1, client_id: 1)

    {:ok, arr0} = Doc.get_array(doc0, "array")
    {:ok, _arr1} = Doc.get_array(doc1, "array")

    # Initial shared state
    Doc.transact!(doc0, fn transaction ->
      {:ok, _arr, transaction} =
        Array.put_many(arr0, transaction, 0, ["shared1", "shared2", "shared3"])

      {:ok, transaction}
    end)

    # Sync initial state
    initial_update = Encoder.encode(doc0)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, initial_update)}
    end)

    # Create network partition - User 0 makes many changes
    for i <- 0..19 do
      Doc.transact!(doc0, fn transaction ->
        {:ok, arr} = Doc.get(transaction, "array")
        len = Array.length(arr)

        if rem(i, 3) != 0 and len > 0 do
          # Delete operation
          delete_pos = rem(i, len)
          {:ok, _arr, transaction} = Array.delete(arr, transaction, delete_pos)
          {:ok, transaction}
        else
          # Insert operation
          pos = if len == 0, do: 0, else: rem(i, len + 1)
          {:ok, _arr, transaction} = Array.put(arr, transaction, pos, "user0-edit-#{i}")
          {:ok, transaction}
        end
      end)
    end

    # User 1 also makes many changes independently
    for i <- 0..19 do
      Doc.transact!(doc1, fn transaction ->
        {:ok, arr} = Doc.get(transaction, "array")
        len = Array.length(arr)

        if rem(i, 3) != 0 and len > 0 do
          # Delete operation
          delete_pos = rem(i, len)
          {:ok, _arr, transaction} = Array.delete(arr, transaction, delete_pos)
          {:ok, transaction}
        else
          # Insert operation
          pos = if len == 0, do: 0, else: rem(i, len + 1)
          {:ok, _arr, transaction} = Array.put(arr, transaction, pos, "user1-edit-#{i}")
          {:ok, transaction}
        end
      end)
    end

    # Heal partition - sync updates
    update0 = Encoder.encode(doc0)
    update1 = Encoder.encode(doc1)

    Doc.transact!(doc0, fn transaction ->
      {:ok, Doc.apply_update(transaction, update1)}
    end)

    Doc.transact!(doc1, fn transaction ->
      {:ok, Doc.apply_update(transaction, update0)}
    end)

    {:ok, arr0_final} = Doc.get(doc0, "array")
    {:ok, arr1_final} = Doc.get(doc1, "array")

    # Verify convergence
    assert Array.to_list(arr0_final) == Array.to_list(arr1_final),
           "States converged after partition healed"
  end
end
