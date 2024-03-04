defmodule Y.ID do
  alias __MODULE__
  alias Y.Item
  defstruct client: 0, clock: 0

  def new(client, clock), do: %ID{client: client, clock: clock}

  def equal?(nil, nil), do: true

  def equal?(
        %Y.ID{client: client1, clock: clock1},
        %Y.ID{client: client2, clock: clock2}
      ) do
    client1 == client2 and clock1 == clock2
  end

  def equal?(_, _), do: false

  def within?(%ID{client: client, clock: clock}, %Item{
        id: %{client: i_client, clock: i_clock},
        length: i_len
      }) do
    i_client == client && clock >= i_clock && clock < i_clock + i_len
  end
end
