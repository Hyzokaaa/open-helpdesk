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
- **Simple** — clean, modern interface anyone understands in minutes
- **Open** — self-host with full control, or use our managed cloud
- **Complete** — all the features your team needs, ready out of the box
- **Affordable** — generous free tier, transparent pricing, no per-agent surprises

## Features

- **Ticket Management** — Full lifecycle: create, assign, track, resolve, discard. Priority, categories, custom fields
- **Reports & CSAT** — Resolution metrics, agent performance, charts, and customer satisfaction surveys
- **Canned Responses** — Predefined replies with "/" quick inserter for faster agent responses
- **Custom Fields** — 6 field types (text, number, select, multi-select, date, checkbox) per workspace
- **Audit Log** — Track every action across your workspace with detailed metadata
- **Roles & Permissions** — 20+ granular permissions across 3 roles (Admin, Agent, Reporter)
- **Workspaces** — Multi-tenant isolation with custom color palettes and branding
- **Invitations** — Invite team members by email with batch support and auto-accept on signup
- **Comments & Mentions** — Mention teammates with autocomplete. XSS-sanitized content
- **Email Notifications** — Configurable per-event with SMTP support
- **In-App Notifications** — Real-time polling, mark as read, per-event preferences
- **File Attachments** — S3-compatible storage, drag & drop, clipboard paste, image lightbox
- **Tags** — Color-coded tags per workspace for flexible organization
- **Dark Mode** — 5 theme options: System, Light, Light Border, Dark, Dark Deep
- **i18n** — Full English and Spanish translations, including email templates

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
| [open-helpdesk-backend](https://github.com/Hyzokaaa/open-helpdesk-backend) | NestJS API — clean architecture, domain services, unit tests |
| [open-helpdesk-client](https://github.com/Hyzokaaa/open-helpdesk-client) | React SPA — custom UI components, i18n, dark mode |
| [open-helpdesk-landing](https://github.com/Hyzokaaa/open-helpdesk-landing) | Landing page — GitHub Pages |

## Get Started

### Option 1: Managed Cloud

Sign up at [openhelpdesk.dev](https://openhelpdesk.dev) and get a free workspace in 30 seconds. No credit card required.

### Option 2: Self-Hosting

```bash
git clone https://github.com/Hyzokaaa/open-helpdesk.git
cd open-helpdesk
cp .env.example .env
docker compose up -d
```

That's it. Open [localhost](http://localhost) for the app, API runs on port 3000.

Default admin: `admin@admin.com` / `admin1234` — change these in `.env` before going to production.

### Configuration

All settings are in `.env`. The defaults work out of the box for local use. For production, you should change:

| Variable | Description |
|----------|-------------|
| `JWT_SECRET` | Secret key for authentication tokens |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | Initial admin credentials |
| `DB_PASSWORD` | Database password |
| `SMTP_*` | Email server for notifications |
| `FRONTEND_URL` | Public URL of your deployment |
| `VITE_API_URL` | Backend URL the client connects to |

See [`.env.example`](.env.example) for all available options.

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
