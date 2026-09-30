# VAYNEX — Backend Prototype

**Agentic AI Public Infrastructure Intelligence Platform**

Vaynex is a decision-support intelligence layer that connects infrastructure,
public services, their dependencies, live events, incidents, risk analysis and
AI intelligence, and turns them into prioritised recommendations for an
authorized human operator.

> **Advisory only.** Vaynex never controls physical infrastructure. Every
> recommendation must be accepted or rejected by a human operator, and every
> decision is audited.

```
Event → Infrastructure context → Dependency analysis → Incident detection → Risk assessment
      → AI intelligence → Recommendations → Human decision → Audit
```

---

## Contents

1. [Architecture](#architecture)
2. [Folder structure](#folder-structure)
3. [Technology stack](#technology-stack)
4. [Quick start (Docker)](#quick-start-docker)
5. [Local development (without Docker for the API)](#local-development)
6. [Environment configuration](#environment-configuration)
7. [Database migrations](#database-migrations)
8. [Seed data & demo credentials](#seed-data--demo-credentials)
9. [Authentication & roles](#authentication--roles)
10. [API endpoints](#api-endpoints)
11. [Simulation demo](#simulation-demo)
12. [Frontend integration](#frontend-integration)
13. [Testing](#testing)
14. [Troubleshooting](#troubleshooting)

---

## Architecture

A **modular monolith**: one FastAPI process, strict layering, no microservices.

```
Frontend (localhost:3000)
   │  REST / JSON  (JWT Bearer)
   ▼
FastAPI  ── middleware: request-id, CORS, error envelope
   │
   ├── API routers (/api/v1/...)          thin: validation + auth only
   ▼
Service layer                            business logic
   ├── Event Service ──────────┐  (pipeline orchestrator)
   ├── Dependency Service      │  graph + cascading impact
   ├── Incident Service        │  detection, lifecycle, status reflection
   ├── Risk Service ───────────┼─► packages/risk        deterministic engine
   ├── Intelligence Service ───┼─► packages/intelligence AIProvider (Mock | OpenAI)
   ├── Recommendation Service  │  rule engine + AI, operator decisions
   ├── Simulation / Dashboard  │
   └── Audit Service ◄─────────┘  append-only trail
   ▼
Repository layer (packages/database/repositories)   all SQL lives here
   ▼
PostgreSQL 16 + PostGIS          Redis 7 (dashboard cache, optional)
```

More detail: [`docs/architecture.md`](docs/architecture.md).

## Folder structure

```
vaynex-backend/
├── apps/api/                  FastAPI application
│   ├── main.py                app factory (create_app) + lifespan
│   ├── core/                  config, logging, errors, middleware, security, cache
│   ├── dependencies/          DB session, auth / role dependencies
│   ├── api/v1/                routers (one file per resource)
│   ├── schemas/               Pydantic v2 request/response models
│   └── services/              business logic (+ demo_data.py, mappers.py)
├── packages/
│   ├── database/              models, repositories, session, Alembic migrations
│   ├── security/              Argon2id hashing, JWT
│   ├── intelligence/          AIProvider interface, MockAIProvider, OpenAIProvider, prompts
│   ├── risk/                  deterministic risk engine + rule catalogue
│   └── common/                enums, constants, utils
├── scripts/                   seed_demo.py, start.py (container entrypoint)
├── tests/                     unit/ and integration/
├── docs/                      architecture.md, api.md, demo.md
├── docker/postgres/           test-database init script
├── Dockerfile, docker-compose.yml, alembic.ini, pyproject.toml, .env.example
```

## Technology stack

| Concern        | Choice |
|----------------|--------|
| Language       | Python 3.12+ |
| Web            | FastAPI, Pydantic v2, Uvicorn |
| Database       | PostgreSQL 16 + PostGIS 3.4, SQLAlchemy 2.x (async), asyncpg, GeoAlchemy2 |
| Migrations     | Alembic (async env) |
| Cache          | Redis 7 (graceful degradation when unavailable) |
| Security       | PyJWT (HS256), Argon2id (argon2-cffi), role-based access |
| AI             | Provider abstraction; deterministic mock by default, OpenAI optional (via httpx) |
| Tests          | pytest + anyio, httpx ASGI client |
| Packaging      | Docker, Docker Compose |

## Quick start (Docker)

Requirements: Docker Desktop (Compose v2.24+).

```bash
cd vaynex-backend
cp .env.example .env          # optional – defaults work for local demo
docker compose up --build
```

The API container automatically runs `alembic upgrade head`, seeds the demo
data (`SEED_DEMO_DATA=true`) and starts Uvicorn.

| Service  | URL / port |
|----------|-----------|
| API      | http://localhost:8000 |
| Swagger  | http://localhost:8000/docs |
| ReDoc    | http://localhost:8000/redoc |
| Postgres | localhost:**5433** (container 5432) — db/user/password `vaynex` |
| Redis    | localhost:**6380** (container 6379) |

All three services have health checks (`docker compose ps`).

Useful commands:

```bash
docker compose logs -f api                              # follow API logs
docker compose exec api alembic upgrade head            # run migrations manually
docker compose exec api python scripts/seed_demo.py     # (re)seed – idempotent
docker compose exec api pytest                          # full test-suite inside the container
docker compose down                                     # stop
docker compose down -v                                  # stop and wipe the database volume
```

## Local development

Run Postgres + Redis in Docker and the API on your machine:

```bash
docker compose up -d postgres redis
python -m venv .venv && source .venv/bin/activate      # Windows: .venv\Scripts\activate
pip install -e ".[dev]"   # or: pip install fastapi "uvicorn[standard]" ... (see pyproject.toml)

# point the app at the host ports
export DATABASE_URL=postgresql+asyncpg://vaynex:vaynex@localhost:5433/vaynex
export REDIS_URL=redis://localhost:6380/0
# Windows PowerShell:  $env:DATABASE_URL="postgresql+asyncpg://vaynex:vaynex@localhost:5433/vaynex"

alembic upgrade head
python scripts/seed_demo.py
uvicorn apps.api.main:app --reload --port 8000
```

## Environment configuration

All settings come from environment variables (or `.env`). See
[`.env.example`](.env.example).

| Variable | Default | Notes |
|----------|---------|-------|
| `ENVIRONMENT` | development | `production` refuses a weak `JWT_SECRET_KEY` |
| `DATABASE_URL` | `postgresql+asyncpg://vaynex:vaynex@localhost:5433/vaynex` | compose overrides with `postgres:5432` |
| `REDIS_URL` | `redis://localhost:6380/0` | empty → caching disabled |
| `JWT_SECRET_KEY` | `change-me-in-development` | **change for anything shared** |
| `JWT_ACCESS_TOKEN_EXPIRE_MINUTES` | 60 | |
| `AI_PROVIDER` | auto | `auto` = OpenAI if key present, else mock |
| `OPENAI_API_KEY` | *(empty)* | optional; never logged |
| `OPENAI_MODEL` | gpt-4o-mini | |
| `CORS_ALLOWED_ORIGINS` | `["http://localhost:3000"]` | JSON list or comma-separated |
| `DASHBOARD_CACHE_TTL_SECONDS` | 15 | |
| `SEED_DEMO_DATA` | true (compose) | seed on container start |

## Database migrations

A single clean initial migration creates every table, index, the PostGIS
extension and GiST spatial indexes:
`packages/database/alembic/versions/20260928_0001_initial_schema.py`.

```bash
alembic upgrade head          # apply
alembic downgrade base        # drop all Vaynex tables (keeps the postgis extension)
alembic upgrade head --sql    # print the SQL without a database
alembic revision --autogenerate -m "describe change"   # future changes
```

Tables: `users`, `organizations`, `infrastructure` (PostGIS `POINT, 4326`),
`services`, `dependencies`, `events` (PostGIS `POINT, 4326`), `incidents`,
`risks`, `recommendations`, `audit_logs`.

## Seed data & demo credentials

`python scripts/seed_demo.py` (idempotent) creates a Hyderabad scenario:

* **Organizations:** Hyderabad Municipal Operations · Hyderabad Emergency Healthcare Network ·
  Telangana Power Operations · Regional Water Authority · Telecom Operations Network
* **Infrastructure:** Hyderabad Central Hospital · Central Power Substation · Water Treatment Plant ·
  Telecom Tower · Emergency Services Center · Critical Road (with real coordinates)
* **Public services:** Emergency Healthcare, Hospital Clinical Services, Electricity Distribution,
  Water Supply Service, Telecommunications, Emergency Communications, Emergency Response & Dispatch,
  Urban Mobility Corridor
* **12 dependencies** e.g. Substation → Hospital (POWER, CRITICAL) → Emergency Healthcare

**Demo accounts** (development only — override with `DEMO_ADMIN_PASSWORD`,
`DEMO_OPERATOR_PASSWORD`, `DEMO_VIEWER_PASSWORD`; the seed refuses to create
them when `ENVIRONMENT=production`):

| Role | Email | Password |
|------|-------|----------|
| ADMIN | `admin@vaynex.local` | `VaynexAdmin!2026` |
| OPERATOR | `operator@vaynex.local` | `VaynexOperator!2026` |
| VIEWER | `viewer@vaynex.local` | `VaynexViewer!2026` |

## Authentication & roles

* `POST /api/v1/auth/register` → creates a **VIEWER** (always).
* `POST /api/v1/auth/login` → `{access_token, token_type, expires_in, user}`.
* Send `Authorization: Bearer <access_token>` on every other call.
* Passwords are hashed with **Argon2id**; tokens are HS256 JWTs with `sub`, `role`, `exp`, `iss`, `jti`.

| Role | Can do |
|------|--------|
| VIEWER | read everything except the audit log |
| OPERATOR | + ingest events, run simulations, create/update infrastructure, services, dependencies, update/resolve incidents, decide recommendations, re-run AI, read audit |
| ADMIN | + create organizations, delete infrastructure (full prototype access) |

In Swagger: call `/auth/login`, click **Authorize**, paste the `access_token`.

## API endpoints

All business endpoints are under `/api/v1`. Full reference with example
payloads: [`docs/api.md`](docs/api.md).

| Area | Endpoints |
|------|-----------|
| Health | `GET /health`, `GET /health/ready` |
| Auth | `POST /auth/register`, `POST /auth/login`, `GET /auth/me` |
| Organizations | `POST/GET /organizations`, `GET /organizations/{id}` |
| Infrastructure | `POST/GET /infrastructure`, `GET/PATCH/DELETE /infrastructure/{id}`, `GET /infrastructure/{id}/dependencies` |
| Services | `POST/GET /services`, `GET/PATCH /services/{id}` |
| Dependencies | `POST/GET /dependencies`, `GET /dependencies/{id}`, `GET /dependencies/graph` |
| Events | `POST/GET /events`, `GET /events/{id}` |
| Incidents | `GET /incidents`, `GET/PATCH /incidents/{id}`, `POST /incidents/{id}/resolve` |
| Risk | `GET /risk/incidents/{id}`, `POST /risk/incidents/{id}/recalculate`, `POST /risk/evaluate` |
| Intelligence | `POST /intelligence/analyze/{incident_id}`, `GET /intelligence/provider` |
| Recommendations | `GET /recommendations`, `GET/PATCH /recommendations/{id}` |
| Dashboard | `GET /dashboard/overview` |
| Simulation | `GET /simulation/scenarios`, `POST /simulation/run` |
| Audit | `GET /audit` |

Lists return `{items, total, limit, offset}` (`limit` ≤ 200). Errors always
return:

```json
{"error": {"code": "RESOURCE_NOT_FOUND", "message": "Incident not found", "request_id": "…"}}
```

Status codes used: 400, 401, 403, 404, 409, 422, 500. Every response carries an
`X-Request-ID` header (send your own to correlate frontend logs).

### Risk engine

Deterministic, explainable, 0–100 (see `packages/risk/engine.py`):

| Factor | Max points |
|--------|-----------|
| Event severity | 25 |
| Origin infrastructure criticality | 25 |
| Strongest dependency in the cascade | 15 |
| Affected infrastructure (criticality × impact weight, saturates at 4.0) | 15 |
| Affected services (criticality × impact weight, saturates at 5.0) | 20 |

Weights LOW 0.25 · MEDIUM 0.5 · HIGH 0.75 · CRITICAL 1.0.
Levels: **0–29 LOW · 30–59 MEDIUM · 60–79 HIGH · 80–100 CRITICAL**. Each result
stores `score, level, impact_score, likelihood_score, explanation, factors[]`.

### AI intelligence

`AIProvider.analyze_incident(context) → {summary, potential_impact, affected_services,
recommended_actions, reasoning, confidence}`.

* `MockAIProvider` (default) – deterministic, template-driven, context-aware; no key needed.
* `OpenAIProvider` – used when `OPENAI_API_KEY` is set (`AI_PROVIDER=auto|openai`); JSON-mode
  Chat Completions; on any error it falls back to the mock provider (`provider: "mock-fallback"`).
* Only operational metadata is sent to the AI (whitelisted payload keys; never user data or secrets).

## Simulation demo

```bash
# 1. login as operator
TOKEN=$(curl -s -X POST localhost:8000/api/v1/auth/login -H 'Content-Type: application/json' \
  -d '{"email":"operator@vaynex.local","password":"VaynexOperator!2026"}' | python -c "import sys,json;print(json.load(sys.stdin)['access_token'])")

# 2. run the primary scenario
curl -s -X POST localhost:8000/api/v1/simulation/run -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"scenario":"hospital_power_failure"}'
```

| Scenario | Chain | Typical result |
|----------|-------|----------------|
| `hospital_power_failure` | Central Power Substation → Hyderabad Central Hospital → Emergency Healthcare | **CRITICAL (~92)** |
| `water_supply_disruption` | Water Treatment Plant → Water Supply Service → Hospital / public services | HIGH (~77) |
| `telecom_outage` | Telecom Tower → Telecommunications → Emergency Communications | HIGH (~63) |
| `flood_infrastructure_risk` | Flood on Critical Road + PostGIS 1.5 km radius → Hospital, Substation, Emergency Services Center | CRITICAL (~87) |

The simulator runs the **real** event pipeline. If the demo topology is missing
it is provisioned automatically. The response contains `simulation_id, event,
incident, risk, affected_infrastructure, affected_services, ai_analysis,
recommendations, human_decision, timeline[], audit`. Step-by-step hackathon
script: [`docs/demo.md`](docs/demo.md).

## Frontend integration

The web app lives in [`apps/web`](apps/web/README.md) (Next.js 15, TypeScript, Tailwind, TanStack Query,
Zustand, React Flow, React Three Fiber). Run it next to the backend:

```bash
docker compose up --build                 # terminal 1: API :8000 (+ Postgres/PostGIS, Redis, seed)
cd apps/web && npm install && npm run dev # terminal 2: UI  :3000  (NEXT_PUBLIC_API_URL=http://localhost:8000)
```

Optional: `docker compose --profile web up --build` also builds and serves the UI container.
Endpoint-by-endpoint contract used by the UI: [`docs/frontend-backend-contract.md`](docs/frontend-backend-contract.md).

* Base URL: `http://localhost:8000/api/v1` — CORS allows `http://localhost:3000` (configurable).
* Login → store `access_token` → `Authorization: Bearer …` header. On `401` redirect to login.
* Suggested screens and their calls:

| Screen | Calls |
|--------|-------|
| Login | `POST /auth/login` |
| Dashboard | `GET /dashboard/overview` (poll every 10–15 s) |
| Infrastructure map | `GET /infrastructure` (lat/lon on every item) |
| Dependency graph | `GET /dependencies/graph` (nodes + edges ready for a graph library) |
| Simulate | `GET /simulation/scenarios`, `POST /simulation/run` (animate `timeline[]`) |
| Incident view | `GET /incidents`, `GET /incidents/{id}` |
| Operator decision | `PATCH /recommendations/{id}` with `{"status":"ACCEPTED"|"REJECTED"|"COMPLETED","note":"…"}` |
| Audit log | `GET /audit` |

* Enums are plain upper-case strings; timestamps are ISO-8601 UTC; ids are UUIDs.
* OpenAPI schema for client generation: `GET /openapi.json`.

## Testing

```bash
pytest tests/unit                 # no external services needed
pytest                            # unit + integration (needs Postgres/PostGIS on :5433; Redis on :6380 optional)
docker compose exec api pytest    # inside the stack (uses vaynex_test database)
```

Integration tests use the `vaynex_test` database (`TEST_DATABASE_URL`) and are
**skipped automatically** if it is unreachable. Tables are recreated at session
start and truncated before each test. Set `VAYNEX_TEST_USE_EXISTING_SCHEMA=1` to
test against a schema created by `alembic upgrade head` instead.

Suite: 64 tests (32 unit, 32 integration) covering auth, hashing, JWT, roles,
risk engine, AI providers, scenarios, graph propagation, every resource API,
event pipeline, incidents, operator decisions, simulation, dashboard caching
and Redis-down degradation.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `port is already allocated` (5433/6380/8000) | stop the other service or change the host port in `docker-compose.yml` |
| API exits with `connection refused` on startup | Postgres still initialising — compose waits for health; run `docker compose up` again |
| `type "geometry" does not exist` | the database lacks PostGIS — use the `postgis/postgis` image, or `CREATE EXTENSION postgis;` |
| Integration tests skipped | start Postgres (`docker compose up -d postgres`) or set `TEST_DATABASE_URL` |
| `vaynex_test` missing (existing volume) | `docker compose exec postgres psql -U vaynex -c "CREATE DATABASE vaynex_test"` |
| Dashboard `cached` always false | Redis unreachable — the API keeps working; check `GET /health/ready` |
| `401 INVALID_TOKEN` after restart | tokens are signed with `JWT_SECRET_KEY`; if it changed, log in again |
| CORS errors in the browser | add your origin to `CORS_ALLOWED_ORIGINS` |
| Apple Silicon: slow Postgres | the PostGIS image is amd64; it runs under emulation — fine for a demo |
| Want to reset the demo | `docker compose down -v && docker compose up --build` |

---

Future roadmap (intentionally **not** in this prototype): streaming ingestion
(Kafka), background workers, multi-tenant RBAC, SSO/MFA, notification
channels, knowledge graph, real government/SCADA integrations.
