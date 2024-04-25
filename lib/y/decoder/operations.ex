defmodule Y.Decoder.Operations do
  import Bitwise

  def read_uint(msg) do
    {_num, _rest} = do_read_uint(msg, 0, 1)
  end

  def read_uint_array(<<s::size(8), msg::binary>>) when s == 0, do: {<<>>, msg}

  def read_uint_array(<<s::size(8), msg::binary>>) do
    <<a::binary-size(s), rest::binary>> = msg
    {a, rest}
  end

  def read_int(<<r::size(8), rest::binary>>) do
    num = r &&& 63
    mult = 64
    sign = if (r &&& 64) > 0, do: -1, else: 1

    if (r &&& 128) == 0 do
      {sign * num, rest}
    else
      {num, rest} = do_read_uint(rest, num, mult)
      {num * sign, rest}
    end
  end

  def read_raw_string(<<r::size(8), rest::binary>>) do
    <<s::binary-size(^r), rest::binary>> = rest
    {s, rest}
  end

  # CASE 127: undefined
  def read_any(<<127, rest::binary>>), do: {nil, rest}
  # CASE 126: null
  def read_any(<<126, rest::binary>>), do: {nil, rest}
  # CASE 125: integer
  def read_any(<<125, rest::binary>>), do: read_int(rest)
  # CASE 124: float32
  def read_any(<<124, f::float-size(32), rest::binary>>), do: {f, rest}
  # CASE 123: float64
  def read_any(<<123, f::float, rest::binary>>), do: {f, rest}
  # CASE 122: bigint
  def read_any(<<122, i::integer-size(64), rest::binary>>), do: {i, rest}
  # CASE 121: boolean (false)
  def read_any(<<121, rest::binary>>), do: {false, rest}
  # CASE 120: boolean (true)
  def read_any(<<120, rest::binary>>), do: {true, rest}
  # CASE 119: string
  def read_any(<<119, rest::binary>>), do: read_raw_string(rest)
  # CASE 118: map<string,any>
  def read_any(<<118, rest::binary>>) do
    {len, rest} = read_uint(rest)

    Enum.reduce(1..len//1, {%{}, rest}, fn _, {m, rest} ->
      {k, rest} = read_raw_string(rest)
      {v, rest} = read_any(rest)
      {Map.put_new(m, k, v), rest}
    end)
  end

  # CASE 117: array<any>
  def read_any(<<117, rest::binary>>) do
    {len, rest} = read_uint(rest)

    {arr, rest} =
      Enum.reduce(1..len//1, {[], rest}, fn _, {arr, rest} ->
        {v, rest} = read_any(rest)
        {[v | arr], rest}
      end)

    {Enum.reverse(arr), rest}
  end

  # CASE 116: Uint8Array
  def read_any(<<116, rest::binary>>), do: read_uint_array(rest)

  def do_read_uint(<<r::size(8), rest::binary>>, num, mult) do
    num = num + (r &&& 127) * mult
    if r < 128, do: {num, rest}, else: do_read_uint(rest, num, mult * 128)
  end
end
