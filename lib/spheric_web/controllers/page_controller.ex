defmodule SphericWeb.PageController do
  use SphericWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
