<div align="center">

# Open Helpdesk

**Complete without being complex.**

The open-source helpdesk for modern teams. Everything you need, nothing you don't.

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0)

[Get Started](#get-started) · [Features](#features) · [Self-Hosting](#self-hosting) · [Contributing](#contributing)

</div>

---

## What is Open Helpdesk?

Open Helpdesk is a full-featured, multi-tenant helpdesk system built for teams that want powerful support tools without the complexity of enterprise solutions.

**Why Open Helpdesk?**
- Zendesk costs $55/agent and takes a week to configure
- osTicket looks like it was built in 2008
- Freshdesk has 200 settings you'll never touch

Open Helpdesk gives you everything that actually matters — in a clean, beautiful interface anyone understands in 2 minutes.

## Features

- **Ticket Management** — Full lifecycle: create, assign, track, resolve, close. Soft delete, status transitions, priority, categories
- **Roles & Permissions** — 20 granular permissions across 3 roles (Admin, Agent, Reporter). System admin for global management
- **Workspaces** — Multi-tenant isolation with slug URLs. Each workspace has its own tickets, tags, members
- **@Mentions & Comments** — Mention teammates in comments with autocomplete. XSS-sanitized content
- **Email Notifications** — Configurable per-event (ticket created, assigned, status changed, comment). SMTP and Postmark support
- **In-App Notifications** — Bell icon with real-time polling, mark as read, per-event preferences
- **File Attachments** — S3-compatible storage, drag & drop, clipboard paste, image lightbox with zoom/pan
- **Tags** — Color-coded tags per workspace for flexible organization
- **Dark Mode** — 5 theme options: System, Light, Light Border, Dark, Dark Deep
- **i18n** — Full English and Spanish translations, including email templates
- **Settings** — Modular settings: Account, Security, Preferences, Notifications

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | NestJS, TypeORM, PostgreSQL |
| Frontend | React 19, Vite, Tailwind CSS 4 |
| Storage | S3-compatible (AWS, MinIO, Hetzner) |
| Email | SMTP / Postmark |
| Auth | JWT with refresh tokens |
| Deploy | Docker, Coolify |

## Repositories

| Repository | Description |
|-----------|-------------|
| [open-helpdesk-backend](https://github.com/Hyzokaaa/open-helpdesk-backend) | NestJS API — clean architecture, domain services, 68+ unit tests |
| [open-helpdesk-client](https://github.com/Hyzokaaa/open-helpdesk-client) | React SPA — custom UI components, i18n, dark mode |

## Get Started

### Option 1: Managed Hosting (Coming Soon)

Sign up at [openhelpdesk.dev](#) and get a free workspace in 30 seconds. No credit card required.

### Option 2: Self-Hosting

Clone both repositories and run with Docker:

```bash
# Clone
git clone https://github.com/Hyzokaaa/open-helpdesk-backend.git
git clone https://github.com/Hyzokaaa/open-helpdesk-client.git

# Backend
cd open-helpdesk-backend
cp .env.example .env        # Configure your environment
docker compose up -d         # Start PostgreSQL + MinIO
npm install
npm run migration:run        # Run database migrations
npm run start:dev            # Start API server

# Client (in another terminal)
cd open-helpdesk-client
cp .env.example .env         # Set VITE_API_URL
npm install
npm run dev                  # Start frontend
```

### Environment Variables

**Backend (.env):**
```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=open_helpdesk
DB_USER=postgres
DB_PASSWORD=postgres

JWT_SECRET=your-secret-key
JWT_EXPIRATION=1d

S3_ENDPOINT=http://localhost:9000
S3_BUCKET=helpdesk-attachments
S3_REGION=us-east-1
S3_ACCESS_KEY=minioadmin
S3_SECRET_KEY=minioadmin

ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=changeme

EMAIL_PROVIDER=smtp
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USER=user
SMTP_PASSWORD=password
EMAIL_FROM=Helpdesk <support@example.com>
```

**Client (.env):**
```env
VITE_API_URL=http://localhost:3000
```

## Architecture

The backend follows clean architecture with strict layer separation:

```
src/
  <module>/
    domain/          # Entities, repositories (interfaces), services (business logic)
    application/     # Commands and queries (use case orchestration)
    infrastructure/  # Controllers, TypeORM models, repository implementations
```

- **Domain services** contain all business logic — no framework dependencies
- **Commands/Queries** orchestrate use cases — no entity mutation, no framework imports
- **Controllers** are pure wiring — inject dependencies, instantiate commands, return results

## Contributing

Contributions are welcome! Open Helpdesk is licensed under [AGPL-3.0](LICENSE), which means:

- You can use, modify, and self-host freely
- If you offer a modified version as a service, you must publish your changes
- The copyright holder can grant commercial exceptions

To contribute:

1. Fork the relevant repository (backend or client)
2. Create a feature branch
3. Follow the architecture conventions described above
4. Submit a pull request

## License

[AGPL-3.0](LICENSE) © 2026 Luis Miguel (Hyzokaaa)
