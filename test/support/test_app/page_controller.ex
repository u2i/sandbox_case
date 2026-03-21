defmodule SandboxCase.TestApp.PageController do
  use Phoenix.Controller, formats: [:html]

  require Logger

  def index(conn, _params) do
    Logger.info("page controller hit")
    text(conn, "ok")
  end

  def error(conn, _params) do
    Logger.error("something went wrong")
    conn |> put_status(500) |> text("error")
  end
end
