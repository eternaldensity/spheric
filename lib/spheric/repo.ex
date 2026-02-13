defmodule Spheric.Repo do
  use Ecto.Repo,
    otp_app: :spheric,
    adapter: Ecto.Adapters.Postgres
end
