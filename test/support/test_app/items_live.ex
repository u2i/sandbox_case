defmodule SandboxCase.TestApp.ItemsLive do
  use Phoenix.LiveView

  import SandboxCase
  sandbox_on_mount()

  alias SandboxCase.TestApp.{Repo, Item}

  def mount(_params, _session, socket) do
    items = Repo.all(Item)
    {:ok, assign(socket, items: items)}
  end

  def render(assigns) do
    ~H"""
    <ul id="items">
      <li :for={item <- @items}>{item.name}</li>
    </ul>
    """
  end
end
