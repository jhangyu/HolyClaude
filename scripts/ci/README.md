# HolyClaude — Local CI/CD Scripts

Local helper scripts for building, running, and managing HolyClaude.
These live next to (not inside) the runtime container's internal scripts
in `scripts/`.

> The `scripts/` directory at the project root contains runtime scripts
> that are **baked into the Docker image** (`bootstrap.sh`, `entrypoint.sh`,
> `notify.py`, the `fix-*.py` and `patch-*.mjs` files). The `scripts/ci/`
> subdirectory is for **host-side automation** and is not copied into
> the image.

## Requirements

- `bash` ≥ 4
- `docker` with the `docker compose` plugin (`docker compose version`)
- optional: `shellcheck` (used by `lint.sh`)

## Environment

- Project root: `/workspace/holyclaude`
- A `.env` file at the project root is auto-loaded by the scripts that
  need it (notably `dev.sh` for `docker-compose.override.yaml` and `deploy.sh`).
  Reference values: see `/workspace/holyclaude/.env.example`.
- `NO_COLOR=1` — disable ANSI colors in script output.
- `ASSUME_YES=1` / `ASSUME_NO=1` — override interactive confirmations
  (used by `clean.sh`, `stop.sh`).

## Shared library — `lib/common.sh`

Source with `source "${BASH_SOURCE%/*}/lib/common.sh"`. Provides:

| Function                              | Purpose                                                |
|---------------------------------------|--------------------------------------------------------|
| `log_info` / `log_warn` / `log_error` | Color-tagged logging (auto-disabled when `NO_COLOR=1`) |
| `log_step` / `log_dim`                | Section header / dimmed detail line                    |
| `ci_script_dir` / `ci_project_root`   | Resolve the calling script's absolute paths            |
| `load_env <file>`                     | `set -a; source …; set +a` style env loading           |
| `require_cmd <cmd>`                   | Die with a clear message if a command is missing       |
| `confirm <prompt> [default_yes]`      | Interactive y/n, with `ASSUME_YES` / `ASSUME_NO` hooks |
| `ci_cleanup_register` / `ci_cleanup_run` | Run hooks on EXIT                                    |
| `die <msg>`                           | Print error and exit 1                                 |

A global `trap ci_cleanup_run EXIT` is set so registered cleanups run
on success or failure.

## Scripts

### `build.sh` — build the image

```bash
scripts/ci/build.sh                          # default: holyclaude:local, variant=full
scripts/ci/build.sh --tag hc:dev --variant slim
scripts/ci/build.sh --no-cache
scripts/ci/build.sh --push --platform linux/amd64,linux/arm64
```

| Flag                | Default                  | Description                               |
|---------------------|--------------------------|-------------------------------------------|
| `--tag`             | `holyclaude:local`       | Image tag                                 |
| `--variant`         | `full`                   | `full` or `slim` (passed as `VARIANT=`)   |
| `--dockerfile`      | `<root>/Dockerfile`      | Path to Dockerfile                        |
| `--context`         | project root             | Build context                             |
| `--no-cache`        | off                      | Disable Docker build cache                |
| `--platform`        | —                        | Comma-separated list (implies buildx)     |
| `--push`            | off                      | Use `buildx build --push`                 |
| `--load`            | off                      | Use `buildx build --load` (default w/x)   |
| `-h`, `--help`      | —                        | Show help                                 |

### `dev.sh` — start locally

```bash
scripts/ci/dev.sh                  # docker-compose.yaml, detached
scripts/ci/dev.sh --full           # docker-compose.override.yaml + .env (auto-copied from .example)
scripts/ci/dev.sh --build          # rebuild before starting
scripts/ci/dev.sh --no-detach      # foreground
```

| Flag           | Description                                       |
|----------------|---------------------------------------------------|
| `--full`       | Use `docker-compose.override.yaml` (auto-copies from .example) |
| `--build`      | Build images before starting                      |
| `--no-detach`  | Run in foreground                                 |
| `--pull`       | `docker compose pull` before `up`                 |
| `-h`, `--help` | Show help                                         |

The full compose file relies on `HOLYCLAUDE_HOST_PORT`,
`HOLYCLAUDE_HOST_CLAUDE_DIR`, `HOLYCLAUDE_HOST_WORKSPACE_DIR` from `.env`.

### `stop.sh` — stop services

```bash
scripts/ci/stop.sh                 # down
scripts/ci/stop.sh --full          # override compose
scripts/ci/stop.sh --volumes       # down -v (interactive confirm)
```

| Flag                | Description                                |
|---------------------|--------------------------------------------|
| `--full`            | Use `docker-compose.override.yaml`         |
| `--volumes`, `-v`   | Also remove named volumes (confirms)       |
| `--remove-orphans`  | Also remove orphaned containers            |
| `-h`, `--help`      | Show help                                  |

### `logs.sh` — view logs

```bash
scripts/ci/logs.sh                         # follow all, tail 100
scripts/ci/logs.sh --no-follow --tail 500  # one-shot
scripts/ci/logs.sh --service holyclaude    # single service
scripts/ci/logs.sh --timestamps --full
```

| Flag                  | Default  | Description                          |
|-----------------------|----------|--------------------------------------|
| `--follow`, `-f`      | on       | Stream log output                    |
| `--no-follow`         | —        | Print and exit                       |
| `--tail`              | `100`    | Lines to show                        |
| `--service`           | all      | Limit to one service                 |
| `--timestamps`, `-t`  | off      | Prepend timestamps                   |
| `--full`              | off      | Use `docker-compose.override.yaml`   |
| `-h`, `--help`        | —        | Show help                            |

### `clean.sh` — remove resources

```bash
scripts/ci/clean.sh                    # safe: stopped containers + dangling images
scripts/ci/clean.sh --images           # also remove holyclaude* images
scripts/ci/clean.sh --volumes          # also remove volumes (destructive)
scripts/ci/clean.sh --all              # everything
ASSUME_YES=1 scripts/ci/clean.sh --all --dry-run
```

| Flag            | Description                                       |
|-----------------|---------------------------------------------------|
| `--containers`  | Remove stopped `holyclaude` containers            |
| `--images`      | Remove `holyclaude*` and dangling images          |
| `--volumes`     | Remove `holyclaude*` volumes (interactive)        |
| `--all`         | All of the above                                  |
| `--dry-run`     | Print the plan, do not run docker                 |
| `-h`, `--help`  | Show help                                         |

### `test.sh` — run tests

The HolyClaude project has no test suite at the root. This script is a
placeholder and exits 0 with a warning unless a framework is detected.

```bash
scripts/ci/test.sh                  # placeholder, warns, exits 0
scripts/ci/test.sh --inside         # TODO if no --cmd is given
scripts/ci/test.sh --cmd "pytest"   # explicit override
```

Detection order: `Makefile` → `package.json` → `pytest.ini` / `pyproject.toml`
→ `go.mod` → `Cargo.toml`. `TODO: no test framework detected` is the
documented current state.

### `lint.sh` — run lint

```bash
scripts/ci/lint.sh                  # shellcheck all .sh under scripts/ and scripts/ci/
scripts/ci/lint.sh --check path/to/script.sh
scripts/ci/lint.sh --inside         # run shellcheck inside the running container
```

If `shellcheck` is not installed the script prints a warning and exits 0.
`TODO: extend with eslint/ruff/flake8` once project-level configs are added.

### `deploy.sh` — deploy

Default mode is **dry-run**: prints the planned actions without running
them. Use `--prod` to actually execute.

```bash
scripts/ci/deploy.sh                                # dry-run, target=local
scripts/ci/deploy.sh --target compose --prod        # full compose
scripts/ci/deploy.sh --image ghcr.io/me/hc:1.0 --prod
```

Configuration from `.env` (or flags):

| Variable          | Default            | Description                          |
|-------------------|--------------------|--------------------------------------|
| `DEPLOY_TARGET`   | `local`            | `local` (simple) or `compose` (override) |
| `DEPLOY_IMAGE`    | `holyclaude:local` | Image:tag (informational)            |
| `DEPLOY_COMPOSE`  | (auto from target) | Override the compose file            |

> Registry pushes are **not** handled here. The
> `.github/workflows/docker-publish.yml` workflow pushes to Docker Hub
> and GHCR on tagged releases.

## Typical workflows

```bash
# First-time setup
./scripts/ci/build.sh --tag holyclaude:dev
./scripts/ci/dev.sh --build

# Day-to-day
./scripts/ci/logs.sh --follow --service holyclaude
./scripts/ci/stop.sh

# Lint before commit
./scripts/ci/lint.sh

# Clean up everything
ASSUME_YES=1 ./scripts/ci/clean.sh --all
```
