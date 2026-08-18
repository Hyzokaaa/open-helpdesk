<div align="center">

![Open Helpdesk](banner.png)

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

- **Ticket Management** — Full lifecycle: create, assign, pick up, transfer, resolve, discard. Priority, categories, custom fields
- **Kanban Board** — Drag-and-drop board view with custom ordering per column
- **Transfer Requests** — Agents request ticket transfers, recipients accept or reject
- **Knowledge Base** — Help articles organized by category, public portal with search, WYSIWYG editor
- **AI Writing Assistant** — Improve and translate ticket descriptions with any OpenAI-compatible API
- **Reports & CSAT** — Resolution metrics, agent performance, charts, and customer satisfaction surveys
- **SLA Tracking** — Response and resolution time targets per priority with automatic breach detection
- **Canned Responses** — Predefined replies with "/" quick inserter for faster agent responses
- **Custom Fields** — 6 field types (text, number, select, multi-select, date, checkbox) per workspace
- **Audit Log** — Track every action across your workspace with detailed metadata
- **System Logs** — Admin-level logs for platform-wide visibility into system events
- **Date & Timezone Preferences** — Per-user date format and timezone settings
- **Public API & Webhooks** — REST API with scoped API keys and webhook event delivery
- **Customer Portal** — Public ticket form, magic link tracking, embeddable widget
- **Roles & Permissions** — 30+ granular permissions across 4 roles (Admin, Supervisor, Agent, Reporter)
- **Ticket Followers** — Follow tickets for updates, @mentions auto-add followers with read-only access
- **Workspaces** — Multi-tenant isolation with custom color palettes and branding
- **System Email Settings** — Configure SMTP from the Admin UI, no environment variables needed
- **Custom Email Sender** — Send notifications from your own email address via SMTP
- **Invitations** — Invite team members by email, copy invite link, invitation-only signup for selfhosted
- **Comments & Mentions** — Mention teammates with autocomplete, timestamps on every comment
- **Email-to-Ticket (IMAP)** — Customers send an email, a ticket is created. Replies become comments. Universal IMAP polling works with any mail server. Import backlog, poll now, pause/resume controls. Configured entirely from the UI
- **Platform Mailbox** — System-level IMAP catch-all for multi-workspace email routing, no per-workspace config needed
- **Mailbox Address Filtering** — Filter inbound emails by exact address, aliases, or catch-all mode
- **Email Notifications** — Smart notifications only to ticket stakeholders, configurable per-event
- **In-App Notifications** — Real-time polling, click to open ticket, mark as read, per-event preferences
- **Data Migration** — Export and import workspace data between instances with duplicate detection
- **File Attachments** — Filesystem or S3-compatible storage, drag & drop, clipboard paste, image lightbox
- **Tags** — Color-coded tags per workspace for flexible organization
- **SSO / Token Exchange** — Embed Open Helpdesk in your product with single API call authentication
- **Google & Microsoft Sign-In** — One-click OAuth login with multi-frontend redirect support
- **Dark Mode** — 5 theme options: System, Light, Light Border, Dark, Dark Deep
- **i18n** — Full English and Spanish translations, including email templates

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Backend | NestJS, TypeORM, PostgreSQL 18 |
| Frontend | React 19, Vite, Tailwind CSS 4 |
| Storage | Filesystem (default) or S3-compatible (AWS, MinIO, Hetzner) |
| Email | Resend / SMTP / Postmark |
| Auth | JWT with refresh tokens |
| Deploy | Docker, Coolify |

## Repositories

| Repository | Description |
|-----------|-------------|
| [open-helpdesk-backend](https://github.com/Hyzokaaa/open-helpdesk-backend) | NestJS API — clean architecture, domain services, unit tests |
| [open-helpdesk-client](https://github.com/Hyzokaaa/open-helpdesk-client) | React SPA — custom UI components, i18n, dark mode |

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

### Option 3: Manual Deployment (without Docker)

Run without Docker on bare metal. No MinIO needed, attachments are stored on disk.

**Requirements:** Node.js 22+, PostgreSQL 15+, nginx.

#### Quick install (interactive script)

```bash
curl -fsSL https://raw.githubusercontent.com/Hyzokaaa/open-helpdesk/main/install.sh -o install.sh
bash install.sh
```

The script installs everything: backend, client, nginx config, and systemd service. It prompts for database credentials, hostname, and admin account.

You can also install backend and client separately with their own scripts:
- Backend: `curl -fsSL https://raw.githubusercontent.com/Hyzokaaa/open-helpdesk-backend/main/install.sh | bash`
- Client: `curl -fsSL https://raw.githubusercontent.com/Hyzokaaa/open-helpdesk-client/main/install.sh | bash`

#### Manual step-by-step

<details>
<summary>Click to expand manual instructions</summary>

##### 1. Backend

```bash
git clone https://github.com/Hyzokaaa/open-helpdesk-backend.git /opt/open-helpdesk/backend
cd /opt/open-helpdesk/backend
npm install
npm run build
mkdir -p data/storage
```

Create a `.env` file (see [`.env.example`](https://github.com/Hyzokaaa/open-helpdesk-backend/blob/main/.env.example)):

```env
PORT=3000
DB_HOST=localhost
DB_PORT=5432
DB_NAME=open_helpdesk
DB_USER=postgres
DB_PASSWORD=your_db_password
DB_RUN_MIGRATIONS=true
JWT_SECRET=generate-a-long-random-string-here
FRONTEND_URL=https://helpdesk.yourcompany.com
ADMIN_EMAIL=admin@yourcompany.com
ADMIN_PASSWORD=change-this
STORAGE_PROVIDER=filesystem
STORAGE_PATH=/opt/open-helpdesk/backend/data/storage
```

Start the backend:

```bash
node dist/main
```

The first start creates the database and the admin user automatically.

**Run as a service (recommended):**

```ini
# /etc/systemd/system/openhelpdesk-backend.service
[Unit]
Description=Open Helpdesk Backend
After=postgresql.service network.target

[Service]
Type=simple
User=openhelpdesk
WorkingDirectory=/opt/open-helpdesk/backend
EnvironmentFile=/opt/open-helpdesk/backend/.env
ExecStart=/usr/bin/node dist/main
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo useradd --system --no-create-home --shell /bin/false openhelpdesk
sudo chown -R openhelpdesk:openhelpdesk /opt/open-helpdesk/backend
sudo systemctl enable --now openhelpdesk-backend
```

##### 2. Frontend

```bash
git clone https://github.com/Hyzokaaa/open-helpdesk-client.git /opt/open-helpdesk/client
cd /opt/open-helpdesk/client
```

Create a `.env` file:

```env
VITE_API_URL=https://helpdesk.yourcompany.com/api
VITE_APP_NAME=Your Company Helpdesk
```

Build and deploy:

```bash
npm install
npm run build
sudo mkdir -p /var/www/openhelpdesk
sudo cp -r dist/* /var/www/openhelpdesk/
```

##### 3. Nginx

```nginx
server {
    listen 443 ssl;
    server_name helpdesk.yourcompany.com;

    ssl_certificate     /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    root /var/www/openhelpdesk;
    index index.html;

    # Frontend (SPA)
    location / {
        try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location /assets {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }

    # Backend API
    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

##### 4. Verify

Open `https://helpdesk.yourcompany.com` and log in with the admin credentials from your `.env`.

</details>

**Notes:**
- `STORAGE_PROVIDER=filesystem` stores attachments on disk, no S3/MinIO needed
- Email (SMTP) can be configured later from Admin > Settings in the UI
- For SSL, use Let's Encrypt with certbot: `sudo certbot --nginx -d helpdesk.yourcompany.com`
- To update: `git pull`, `npm install`, `npm run build`, restart the service

### Configuration

All settings are in `.env`. The defaults work out of the box for local use. For production, you should change:

| Variable | Description |
|----------|-------------|
| `JWT_SECRET` | Secret key for authentication tokens |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | Initial admin credentials |
| `DB_PASSWORD` | Database password |
| `EMAIL_PROVIDER` | Email provider: `resend`, `smtp`, or `postmark` |
| `EMAIL_API_KEY` | API key for Resend (if using Resend provider) |
| `SMTP_*` | SMTP server for notifications (if using SMTP provider) |
| `FRONTEND_URL` | Public URL of your deployment |
| `VITE_API_URL` | Backend URL the client connects to |
| `VITE_APP_NAME` | App name shown in the UI (default: `Open`) |
| `VITE_APP_SUBTITLE` | Subtitle shown below the name (default: `Helpdesk`) |
| `SUPPORT_EMAIL_DOMAIN` | Domain for auto-generated workspace email addresses (only for Platform Mailbox, see below) |

See [`.env.example`](.env.example) for all available options.

### Email-to-Ticket (optional)

Let your customers create tickets by sending an email. Works with any mail server via IMAP polling — no webhooks or special server configuration needed.

1. Create a dedicated email account (e.g. `support@yourcompany.com`) with any provider (Gmail, Outlook, your own mail server)
2. Go to **Workspace Settings → Mailboxes → Connect Mailbox** and enter the IMAP credentials
3. Send a test email to that address — a ticket should appear in your dashboard

Everything is configured from the UI. No environment variables needed.

**Features per mailbox:**
- **Address filtering** — Process only emails sent to the mailbox address, include aliases, or accept all (catch-all)
- **Encryption** — TLS (validate certificate), TLS (allow self-signed), or None
- **Auto-reply** — Toggle automatic confirmation emails when tickets are created from inbound email
- **Pause / Resume** — Temporarily stop polling without deleting the mailbox
- **Import** — Import all existing emails from the mailbox as tickets

> **Gmail users:** You need an [App Password](https://myaccount.google.com/apppasswords), not your regular password. Enable 2-Step Verification first.

> **How replies work:** When a ticket is created from email, the system adds threading headers so the customer can reply directly to the notification email and their reply becomes a comment on the ticket.

---

### Platform Mailbox (advanced, optional)

> **Most users don't need this.** This is for operators who run their own mail server and want to route emails from multiple workspaces through a single IMAP account. If you just need email-to-ticket for one workspace, use the standard mailbox setup above.

The Platform Mailbox is a system-level IMAP catch-all that automatically routes emails to the correct workspace based on the recipient address. Instead of configuring IMAP per workspace, you configure one mailbox in **Admin → Settings → Email Receiving** and every workspace gets an email address automatically.

**How it works:**

1. You operate a mail server (Stalwart, Postfix, Dovecot, etc.) with a **catch-all** configured — all emails to `*@support.yourdomain.com` land in one IMAP mailbox
2. You configure the Platform Mailbox in **Admin → Settings** pointing to that IMAP account
3. When a workspace is created, it gets an address like `{workspace-slug}@support.yourdomain.com`
4. The poller reads all emails from the catch-all, checks the `To`/`CC` headers, and routes each email to the correct workspace

**Requirements:**

- A mail server you control with catch-all enabled for the support domain
- `SUPPORT_EMAIL_DOMAIN` environment variable set to the support domain (e.g. `support.yourdomain.com`), OR the domain is derived automatically from the Platform Mailbox address
- DNS: MX record for the support domain pointing to your mail server

**Mail server catch-all setup (examples):**

<details>
<summary>Stalwart</summary>

In Stalwart Admin UI → Settings → Listeners → RCPT stage, enable catch-all for the domain. All emails to `*@support.yourdomain.com` will be delivered to the configured account.

</details>

<details>
<summary>Postfix</summary>

Add to `/etc/postfix/virtual`:
```
@support.yourdomain.com   catchall-user@yourdomain.com
```
Then run `postmap /etc/postfix/virtual` and `systemctl reload postfix`.

</details>

<details>
<summary>Dovecot + any MTA</summary>

Configure your MTA to accept all addresses for the domain and deliver to a single Dovecot mailbox. The specific steps depend on your MTA (Postfix, Exim, etc.).

</details>

**Workspace admin controls:**

- Each workspace admin can **disable** the platform mailbox for their workspace (the toggle in Workspace Settings → Mailboxes)
- Disabling only stops tickets from being created via the platform catch-all — their own IMAP mailboxes continue working independently
- If the system admin pauses the Platform Mailbox, all workspaces see it as "paused" and the toggle is disabled

### HTTPS / Reverse Proxy

If you're running behind a reverse proxy (nginx, Caddy, etc.) with HTTPS, you need to proxy both the client and the backend API. Example nginx config:

```nginx
server {
    listen 443 ssl;
    server_name helpdesk.example.com;

    ssl_certificate     /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    # Frontend
    location / {
        proxy_pass http://localhost:80;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Backend API
    location /api/ {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Then set your `.env` accordingly:

```env
FRONTEND_URL=https://helpdesk.example.com
VITE_API_URL=https://helpdesk.example.com/api
```

> **Note:** The trailing slash in `proxy_pass http://localhost:3000/` is important — it strips the `/api/` prefix so the backend receives the correct paths.

### Embed in Your Product (Token Exchange)

You can integrate Open Helpdesk into your own application so your users access the helpdesk without a separate login. This works by exchanging a user's identity from your system for an Open Helpdesk JWT.

#### 1. Create an API key

Go to **Workspace Settings → API Keys** and create a key with the **Token exchange (SSO)** scope (`auth:exchange`).

#### 2. Add one endpoint to your backend

When your user needs to access the helpdesk, your backend calls Open Helpdesk to get a JWT:

```javascript
// Your backend (Express, NestJS, Django, Rails, etc.)
app.get('/api/helpdesk-token', auth, async (req, res) => {
  const response = await fetch('https://your-helpdesk-api/api/v1/auth/exchange', {
    method: 'POST',
    headers: {
      'Authorization': 'Bearer ohd_your_api_key',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email: req.user.email,
      firstName: req.user.firstName,
      lastName: req.user.lastName,
      role: 'agent', // agent, admin, supervisor, or reporter
    }),
  });
  const { accessToken } = await response.json();
  res.json({ token: accessToken });
});
```

#### 3. Use the token in the frontend

```javascript
// Your frontend
const { token } = await fetch('/api/helpdesk-token').then(r => r.json());
localStorage.setItem('access_token', token);
window.location.href = '/helpdesk'; // Your Open Helpdesk client deployment
```

**What happens:**
- If the user doesn't exist in Open Helpdesk, they are automatically created and added to the workspace
- If they already exist, a new JWT is issued
- The user never sees an Open Helpdesk login screen

**Request:**
```
POST /api/v1/auth/exchange
Authorization: Bearer ohd_your_api_key
Content-Type: application/json

{
  "email": "user@company.com",
  "firstName": "Jane",
  "lastName": "Doe",
  "role": "agent"       // optional, defaults to "agent"
}
```

**Response:**
```json
{
  "accessToken": "eyJhbG...",
  "user": { "id": "01J...", "email": "user@company.com" }
}
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
