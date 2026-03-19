defmodule SandboxCase.TestApp.GreetingLive do
  use Phoenix.LiveView

  import SandboxCase
  sandbox_on_mount()

  def mount(_params, _session, socket) do
    greeting = SandboxCase.TestApp.ExternalService.greeting()
    {:ok, assign(socket, greeting: greeting)}
  end

  def render(assigns) do
    ~H"""
    <p id="greeting">{@greeting}</p>
    """
  end
end
