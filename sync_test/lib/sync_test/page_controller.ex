defmodule SyncTest.PageController do
  use Phoenix.Controller, formats: [:html]

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Application.app_dir(:sync_test, "priv/static/index.html"))
  end
end
