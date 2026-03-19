defmodule SandboxCase.TestApp.Layouts do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html><head></head>
    <body>{@inner_content}</body>
    </html>
    """
  end
end
