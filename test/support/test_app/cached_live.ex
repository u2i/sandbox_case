defmodule SandboxCase.TestApp.CachedLive do
  use Phoenix.LiveView

  import SandboxShim
  sandbox_on_mount()

  alias SandboxCase.TestApp.{Repo, Item}

  def mount(_params, _session, socket) do
    items =
      case Cachex.fetch(:test_cache, "items", fn _key ->
             {:commit, Repo.all(Item)}
           end) do
        {:ok, items} -> items
        {:commit, items} -> items
      end

    {:ok, assign(socket, items: items)}
  end

  def render(assigns) do
    ~H"""
    <ul id="cached-items">
      <li :for={item <- @items}>{item.name}</li>
    </ul>
    """
  end
end
