# Server Setup & Administration

This guide covers everything you need to set up, run, and manage a Spheric game server — whether for local development or a public multiplayer instance.

> [!info] For Server Operators
> This page is intended for people hosting a Spheric server, not for players. If you're looking for gameplay help, start with [[What Is Spheric]].

---

## Prerequisites

Before you begin, ensure the following are installed on your machine:

| Dependency | Version | Purpose |
|---|---|---|
| **Elixir** | 1.15+ | Application runtime |
| **Erlang/OTP** | 26+ | Underlying VM |
| **PostgreSQL** | 14+ | World state persistence |
| **Node.js** | 18+ | Asset compilation (esbuild, tailwind) |
| **Git** | Any recent | Fetching source code |

> [!tip] Version Check
> Run `elixir --version` and `psql --version` to confirm your installed versions. On Windows, the Erlang installer bundles OTP automatically.

---

## Initial Setup

### 1. Clone the Repository

```
git clone <your-repo-url> spheric
cd spheric
```

### 2. Install Dependencies and Build

The project provides a single setup command that fetches Elixir dependencies, creates the database, and compiles assets:

```
mix setup
```

This runs the following steps in order:

1. `mix deps.get` — fetch Elixir dependencies
2. `mix ecto.setup` — create the database, run migrations, and seed data
3. `mix assets.setup` — install esbuild and tailwind binaries if missing
4. `mix assets.build` — compile JavaScript and CSS

> [!warning] Database Configuration
> By default, development expects a PostgreSQL instance on **localhost** with username `postgres` and password `postgres`. If your setup differs, edit `config/dev.exs` before running `mix setup`.

### 3. Start the Server

```
mix phx.server
```

The game is now running at **http://localhost:4000**. Open it in your browser to verify.

To start the server inside an interactive Elixir shell (useful for debugging):

```
iex -S mix phx.server
```

---

## Configuration

Spheric uses the standard Phoenix configuration layout:

| File | Purpose |
|---|---|
| `config/config.exs` | Shared settings (endpoint, esbuild, tailwind, logger) |
| `config/dev.exs` | Development overrides (database, live reload, watchers) |
| `config/test.exs` | Test environment (sandbox pool, disabled server) |
| `config/prod.exs` | Production compile-time settings (SSL, static manifests) |
| `config/runtime.exs` | Production runtime settings (read from environment variables) |

### Key Environment Variables (Production)

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | PostgreSQL connection string, e.g. `ecto://user:pass@host/spheric_prod` |
| `SECRET_KEY_BASE` | Yes | 64+ byte secret for signing cookies. Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Yes | Public hostname, e.g. `spheric.example.com` |
| `PORT` | No | HTTP port (defaults to `4000`) |
| `PHX_SERVER` | No | Set to `true` to start the web server in release mode |
| `POOL_SIZE` | No | Database connection pool size (defaults to `10`) |
| `ECTO_IPV6` | No | Set to `true` if your database requires IPv6 |

> [!important] Secret Key Base
> Never reuse the development secret key in production. Always generate a fresh one with `mix phx.gen.secret` and store it securely.

---

## Running in Production

### Option A: Mix (Simple)

For a quick production start without building a release:

```
MIX_ENV=prod mix setup
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix phx.server
```

### Option B: Elixir Release (Recommended)

Releases compile your application into a self-contained package that doesn't require Elixir or Erlang on the target machine.

```
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
```

This creates a release in `_build/prod/rel/spheric/`. Start it with:

```
PHX_SERVER=true _build/prod/rel/spheric/bin/spheric start
```

Or run as a daemon:

```
_build/prod/rel/spheric/bin/spheric daemon
```

> [!tip] Health Check
> After starting, verify the server is running by visiting `http://your-host:4000` or calling `curl http://localhost:4000`.

---

## Database Management

### Migrations

Apply pending database migrations:

```
mix ecto.migrate
```

In production with a release:

```
_build/prod/rel/spheric/bin/spheric eval "Spheric.Release.migrate()"
```

### Reset (Development Only)

Drop and recreate the database with seed data:

```
mix ecto.reset
```

> [!danger] Destructive Operation
> `mix ecto.reset` destroys all world data, player progress, and building state. Only use this in development or when you intentionally want a fresh start.

### Seeding

Re-run the seed script without dropping the database:

```
mix run priv/repo/seeds.exs
```

---

## Administration

### Admin Dashboard

Spheric includes a built-in admin page at **/admin**. From there, server operators can:

- View connected players
- Reset the world state
- Monitor server health

### Interactive Console

Attach to a running server for live debugging:

```
iex -S mix phx.server
```

In a release:

```
_build/prod/rel/spheric/bin/spheric remote
```

This gives you a live Elixir shell connected to the running application, useful for inspecting game state, running ad-hoc queries, or diagnosing issues.

### Logs

In development, logs print to the terminal with the format `[level] message`.

In production, configure your log aggregation service to capture stdout. The default log level is `:info` — adjust in `config/prod.exs` if you need more or less verbosity.

---

## Multiplayer & Networking

Spheric uses **Phoenix LiveView** over WebSockets for real-time communication. Players connect via their browser — no game client installation is required.

### Allowing LAN Access

By default, the development server binds to `127.0.0.1` (localhost only). To allow other machines on your network to connect:

In `config/dev.exs`, change the endpoint binding:

```elixir
http: [ip: {0, 0, 0, 0}]
```

Then share your local IP address (e.g. `http://192.168.1.100:4000`) with other players.

### Port Configuration

The server listens on port **4000** by default. Override it with the `PORT` environment variable:

```
PORT=8080 mix phx.server
```

### Reverse Proxy (Production)

For production deployments, place the server behind a reverse proxy (nginx, Caddy, etc.) that handles SSL termination and forwards WebSocket connections:

```
# Nginx example (minimal)
location / {
    proxy_pass http://127.0.0.1:4000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

> [!warning] WebSocket Support Required
> LiveView requires persistent WebSocket connections. Ensure your proxy passes `Upgrade` and `Connection` headers, and does not set aggressive idle timeouts.

---

## Troubleshooting

**"Database does not exist"** — Run `mix ecto.create` to create it, or `mix ecto.reset` for a full reset.

**"mix: command not found"** — Elixir is not installed or not on your PATH. Install from [elixir-lang.org](https://elixir-lang.org/install.html).

**Assets not compiling** — Run `mix assets.setup` to install the esbuild and tailwind binaries, then `mix assets.build`.

**Port already in use** — Another process is using port 4000. Either stop it or set `PORT=4001 mix phx.server`.

**Players can't connect from other machines** — Check that the endpoint is bound to `{0, 0, 0, 0}` instead of `{127, 0, 0, 1}`, and that your firewall allows traffic on the configured port.

**WebSocket disconnections behind proxy** — Increase your proxy's WebSocket idle timeout and verify the `Upgrade`/`Connection` headers are forwarded.

---

**See also:** [[Controls & Keybindings]], [[Glossary]]
