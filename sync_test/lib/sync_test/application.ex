defmodule SyncTest.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SyncTest.DocServer,
      {Phoenix.PubSub, name: SyncTest.PubSub},
      SyncTest.Endpoint
    ]

    opts = [strategy: :one_for_one, name: SyncTest.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
