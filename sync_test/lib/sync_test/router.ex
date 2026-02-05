defmodule SyncTest.Router do
  use Phoenix.Router

  pipeline :browser do
    plug :accepts, ["html"]
  end

  scope "/", SyncTest do
    pipe_through :browser
    get "/", PageController, :index
  end
end
