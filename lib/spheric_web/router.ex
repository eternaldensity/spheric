defmodule SphericWeb.Router do
  use SphericWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SphericWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SphericWeb do
    pipe_through :browser

    live "/", GameLive
    live "/admin", AdminLive
    live "/guide", GuideLive
    live "/guide/:page", GuideLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", SphericWeb do
  #   pipe_through :api
  # end
end
