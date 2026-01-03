defmodule Y.Encoder.Operations do
  import Bitwise

  def write_uint(acc \\ <<>>, num) do
    if num <= 127 do
      acc <> <<127 &&& num>>
    else
      write_uint(acc <> <<128 ||| (127 &&& num)>>, floor(num / 128))
    end
  end

  def write_int(acc \\ <<>>, num) do
    neg? = if num < 0, do: 64, else: 0
    num = if num < 0, do: -num, else: num
    cont? = if num > 63, do: 128, else: 0
    acc = acc <> <<cont? ||| neg? ||| (63 &&& num)>>

    acc |> do_write_int(floor(num / 64))
  end

  @doc """
  Write a signed integer with explicit sign flag.
  This is needed to encode "negative zero" for RLE encoding of 0 values.
  """
  def write_int_with_sign(acc \\ <<>>, num, is_negative?) do
    neg? = if is_negative?, do: 64, else: 0
    cont? = if num > 63, do: 128, else: 0
    acc = acc <> <<cont? ||| neg? ||| (63 &&& num)>>

    acc |> do_write_int(floor(num / 64))
  end

  def write_bigint(acc \\ <<>>, num), do: acc <> <<num::size(64)>>

  def write_float64(acc \\ <<>>, num), do: acc <> <<num::float-size(64)>>

  def write_byte(acc \\ <<>>, num), do: acc <> <<num::size(8)>>

  def write_string(acc \\ <<>>, s), do: write_uint(acc, byte_size(s)) <> s

  def write_bitstring(acc \\ <<>>, bs), do: write_uint(acc, byte_size(bs)) <> bs

  defp do_write_int(acc, num) when num > 0 do
    do_write_int(acc <> <<if(num > 127, do: 128, else: 0) ||| (127 &&& num)>>, floor(num / 128))
  end

  defp do_write_int(acc, _num), do: acc
end
