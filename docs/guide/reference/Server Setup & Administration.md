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

### Database Not Running

The most common startup failure is PostgreSQL not being available. The server will crash immediately with a `connection refused` error.

**Symptoms:**

- `(DBConnection.ConnectionError) tcp connect (localhost:5432): connection refused - :econnrefused`
- `** (EXIT) an exception was raised: ** (DBConnection.ConnectionError) could not checkout the connection`
- The server starts and immediately exits

**How to fix:**

1. **Check if PostgreSQL is running:**

   On Linux/macOS:
   ```
   pg_isready
   ```

   On Windows:
   ```
   pg_isready -h localhost -p 5432
   ```

   If it reports "no response", PostgreSQL is not running.

2. **Start PostgreSQL:**

   On Linux (systemd):
   ```
   sudo systemctl start postgresql
   ```

   On macOS (Homebrew):
   ```
   brew services start postgresql@14
   ```

   On Windows (services):
   ```
   net start postgresql-x64-14
   ```

   Or open **Services** (Win+R → `services.msc`), find the PostgreSQL service, and click **Start**.

3. **Verify the connection:**
   ```
   psql -U postgres -h localhost -c "SELECT 1;"
   ```

   If this returns `1`, PostgreSQL is running and accepting connections. Start the server again with `mix phx.server`.

> [!tip] Auto-Start
> To avoid this issue in the future, configure PostgreSQL to start automatically with your operating system. On Linux: `sudo systemctl enable postgresql`. On macOS: `brew services start postgresql@14` (persists across reboots). On Windows: set the PostgreSQL service startup type to **Automatic** in Services.

### PostgreSQL Won't Start on Windows (Error 1067)

If you try to start the PostgreSQL service from Windows Services and it fails with **"Error 1067: The process terminated unexpectedly"**, PostgreSQL is crashing during startup — usually due to corrupt data, a bad config, or leftover lock files.

**Step 1: Check the PostgreSQL log.**

The log reveals the actual crash reason. Find it at:

```
C:\Program Files\PostgreSQL\<version>\data\log\
```

or

```
C:\Users\<you>\AppData\Roaming\PostgreSQL\<version>\data\log\
```

Open the most recent `.log` file and look for `FATAL` or `PANIC` lines near the bottom.

**Step 2: Fix based on what the log says.**

**Lock file left behind after a crash:**

The log shows `FATAL: lock file "postmaster.pid" already exists`. A previous PostgreSQL process did not shut down cleanly.

1. Open the `data` directory (same folder that contains `log/`)
2. Delete the file `postmaster.pid`
3. Try starting the service again

**Corrupt WAL or data files:**

The log shows `PANIC: could not locate a valid checkpoint record` or similar corruption messages.

1. If you have a backup, restore from it
2. If this is a development database with no important data, reinitialize:
   ```
   # In an Administrator terminal:
   rd /s /q "C:\Program Files\PostgreSQL\<version>\data"
   "C:\Program Files\PostgreSQL\<version>\bin\initdb.exe" -D "C:\Program Files\PostgreSQL\<version>\data" -U postgres
   ```
   Then start the service again. You'll need to re-run `mix ecto.setup` afterward.

**Port conflict:**

The log shows `FATAL: could not bind to address "127.0.0.1": port 5432 already in use`. Another process (or a second PostgreSQL installation) is already using port 5432.

1. Find the conflicting process:
   ```
   netstat -ano | findstr :5432
   ```
2. Kill it or change PostgreSQL's port in `postgresql.conf` (inside the `data` directory), then restart.

**Wrong data directory permissions:**

The log shows `FATAL: data directory has wrong ownership` or similar permissions errors.

1. Right-click the `data` folder → **Properties** → **Security**
2. Ensure the PostgreSQL service account (usually `Network Service` or a dedicated `postgres` user) has **Full Control**

> [!warning] Multiple PostgreSQL Installations
> If you have more than one PostgreSQL version installed, their services can conflict. Check Services for duplicate entries (e.g. `postgresql-x64-14` and `postgresql-x64-16`). Stop the one you're not using, or change the port in the other's `postgresql.conf`.

**Step 3: Verify recovery.**

After fixing the issue, start the service and confirm:

```
pg_isready -h localhost -p 5432
```

Then start the game server with `mix phx.server`.

### Database Exists But Is Corrupt or Out of Date

If the database exists but the server crashes with migration or schema errors:

**Symptoms:**

- `(Postgrex.Error) ERROR 42P01 (undefined_table)` — a table is missing
- `(Postgrex.Error) ERROR 42703 (undefined_column)` — a column is missing
- `(Ecto.MigrationError)` — migrations are out of sync

**How to fix:**

1. **Run pending migrations:**
   ```
   mix ecto.migrate
   ```

2. **If migrations fail**, the schema may be too far out of sync. Reset the database:
   ```
   mix ecto.reset
   ```

> [!danger] Data Loss
> `mix ecto.reset` drops and recreates the database. All world state, player data, and buildings are lost. Only use this when you're willing to start fresh.

### Connection Pool Exhaustion

Under heavy load or with many concurrent players, the database connection pool can become saturated.

**Symptoms:**

- `(DBConnection.ConnectionError) connection not available and request was dropped from queue after 5000ms`
- The server stays running but individual requests fail or time out

**How to fix:**

1. **Increase the pool size** in your configuration. In `config/dev.exs`:
   ```elixir
   config :spheric, Spheric.Repo,
     pool_size: 20
   ```

   In production, set the `POOL_SIZE` environment variable:
   ```
   POOL_SIZE=20
   ```

2. **Check for slow queries.** Attach to the running server with `iex -S mix phx.server` or `bin/spheric remote` and inspect the Ecto query logs. Long-running queries hold connections and starve others.

3. **Verify external database limits.** Managed database providers (Render, Fly, AWS RDS) impose their own connection limits. Ensure `POOL_SIZE` does not exceed the plan's allowed connections.

### Server Crashes on Startup

If the server exits immediately after starting, check the error output carefully. The most common causes:

**Missing environment variables (production):**

```
** (RuntimeError) environment variable DATABASE_URL is missing.
```

or

```
** (RuntimeError) environment variable SECRET_KEY_BASE is missing.
```

Set all required environment variables listed in the Configuration section above before starting.

**Dependencies not fetched:**

```
** (UndefinedFunctionError) function SomeModule.some_function/1 is undefined (module SomeModule is not available)
```

Run `mix deps.get` to fetch dependencies, then `mix compile`.

**Assets not built:**

The game page loads but shows no sphere, no UI, or a blank screen. JavaScript or CSS assets are missing.

```
mix assets.setup
mix assets.build
```

### Players Disconnecting or Experiencing Lag

**Symptoms:**

- Players report the game freezing, then reconnecting
- LiveView shows "attempting to reconnect" banners
- Intermittent disconnections under load

**How to fix:**

1. **Check server resources.** High CPU or memory usage causes the BEAM VM to slow down, delaying WebSocket heartbeats. Monitor with `htop`, Task Manager, or your hosting provider's dashboard.

2. **Review tick processing time.** If the game's tick loop takes too long, it can block LiveView updates. Check the server logs for warnings about slow ticks.

3. **Proxy timeouts.** If behind a reverse proxy, ensure the WebSocket idle timeout is generous (at least 60 seconds). Nginx example:
   ```
   proxy_read_timeout 86400;
   proxy_send_timeout 86400;
   ```

4. **Network quality.** LiveView requires a stable connection. Players on unstable WiFi or mobile networks will experience more disconnections than those on wired connections.

### Compilation Errors After Updating

After pulling new code from the repository:

```
mix deps.get
mix ecto.migrate
mix assets.build
mix compile
```

If compilation still fails:

```
mix deps.clean --all
mix deps.get
mix compile
```

As a last resort, clear all build artifacts:

```
rm -rf _build deps
mix setup
```

### Quick Reference

| Problem | Command |
|---|---|
| PostgreSQL not running | `pg_isready` then start the service |
| Windows Error 1067 on PG start | Check logs in `data\log\`, delete stale `postmaster.pid`, or reinitialize |
| Database missing | `mix ecto.create` |
| Migrations pending | `mix ecto.migrate` |
| Schema out of sync | `mix ecto.reset` |
| Dependencies missing | `mix deps.get` |
| Assets missing | `mix assets.setup && mix assets.build` |
| Port in use | `PORT=4001 mix phx.server` |
| Can't connect from LAN | Bind to `{0, 0, 0, 0}` in `config/dev.exs` |
| WebSocket drops behind proxy | Forward `Upgrade`/`Connection` headers, increase timeouts |
| Pool exhausted | Increase `POOL_SIZE` or optimize slow queries |
| Build artifacts stale | `rm -rf _build deps && mix setup` |

---

**See also:** [[Controls & Keybindings]], [[Glossary]]
