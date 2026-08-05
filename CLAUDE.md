# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a collection of n8n automation workflow definitions for **SUPRICOM**, a technology wholesaler (mayorista) in Venezuela. All files are JSON exports from an n8n instance at `chatwoot.supricom.com.ve` / `panel.supricom.com.ve`. There is no build system, test runner, or linter — changes are made directly to the JSON files and imported into the live n8n instance.

## Workflow Architecture

The workflows form an integrated lead-capture and customer-service automation system. They share a common MySQL database (`MySQL account` credential, credential ID `D2jBVXzwxDQKZNau`) with these key tables:

- `leads` — all captured leads with fields: `nombre_contacto`, `name` (company), `rif`, `telefono`, `ubicacion_detalle`, `ubicacion_estado`, `seller_id`, `whatsapp_link`, `status`, `canal_origen`, `campana`, `interes`, `identidad`
- `sellers` — sales staff with round-robin assignment logic
- `users_config` — user emails and roles (role_id=8 is the leads admin)
- `leads_status_history` — status change audit trail
- `conversaciones` — tracks Chatwoot conversation IDs and qualification status

### Workflow Summaries

**Carlos Produccion** (`qPJ5YoWf55RxpzfB`) — The core AI sales agent.
- Trigger: Chatwoot webhook at path `/carlos`
- Debounce: Incoming messages are buffered in Redis (list keyed by `conversacion_id`) and processed after 7 seconds of silence
- Agent: OpenAI `o3-mini` acting as "Carlos", a B2B sales representative
- Tools available to the agent: `consultar_productos_sheets` (reads `SUPRICOM_Catalogo_Marcas` Google Sheet) and `registrar_leads_bd` (calls the "Registro de Leads DB" sub-workflow)
- Memory: PostgreSQL chat history keyed by `conversacion_id`
- Outputs back to Chatwoot via HTTP, closes conversation on farewell, marks MySQL `conversaciones.es_calificado`

**Registro de Leads DB** (`MtAK0J8DS5OPuMrd`) — Shared sub-workflow for lead registration, called by Carlos and by other entry points.
- Input fields: `Nombre de Contacto`, `Nombre de la empresa`, `RIF`, `Ubicación`, `WhatsApp`, `Canal`, `Interes`, `Tipo`, `campana`
- Normalizes: RIF to `J-XXXXXXXX` format, WhatsApp to Venezuelan format (`+58...`), location text → Venezuelan state via keyword matching and city aliases
- Splits by region: Caracas/Carabobo/Distrito Capital use stored procedure `asignar_vendedor_rotacion_carcar`; all other states use `asignar_vendedor_rotacion`
- After DB insert: POSTs to `https://panel.supricom.com.ve/api/webhooks/leads-notify` (header `x-webhook-secret: Auto.OSC2026`), then sends Gmail notification to the assigned seller

**Meta - Captura Campaña Instagram** (`gmQSbpwrPMu18wq4`) — Instagram ad campaign attribution.
- Receives Meta webhook POSTs, filters echo messages
- If a referral object is present, stores campaign data in Redis key `meta_campaign:{instagram_id}` with 24h TTL
- Strips referral fields from the payload, re-signs with HMAC-SHA256 (secret: `228924df2407ae6156161cbc74f9570e`), and forwards to Chatwoot's Instagram webhook

**Chatwoot - Cierre o Recordatorio por Último Mensaje** (`f6C0V8r1n7em3gQ7`) — Automated conversation lifecycle management.
- Scheduled every 2 hours
- Fetches open Chatwoot conversations, analyzes last message per conversation
- Logic: if last outgoing message is ≥6h old → send reminder + apply label `recordatorio_enviado`; if labeled + outgoing + >24h → close; if labeled + incoming → remove label; specific closing messages trigger immediate close

**Leads - Form Pagina Web** (`EdxyMeyKruJkUcor`) — Website form webhook receiver.
- Path `/form`, filters for `al_mayor == "Si"` (wholesale buyers only)
- Assigns sellers and inserts into `leads` table directly (does not call the sub-workflow)

**SUPRICOM - Alerta Leads por Tiempo en Status** (`ESl2g2qK5x2PvVoh`) — SLA enforcement alerts.
- Cron: Mon–Fri at 9:00 and 15:00
- Time limits: NUEVO=24h (warning at 2h remaining), CONTACTADO=48h (vencido only), EN NEGOCIACION=72h (vencido only)
- Sends WhatsApp template messages and Gmail alerts to sellers; sends admin email when a NUEVO lead is vencido

**Send Assignment Notification** / **Send Resignation Notification** — Webhook endpoints called by `panel.supricom.com.ve` to trigger Gmail notifications for manual lead assignment/reassignment events.

### Credential Reference

| n8n Name | Type | Used For |
|---|---|---|
| `ChatWoot Acount` | httpHeaderAuth | Read Chatwoot API (account token) |
| `ChatWoot Bot` | httpHeaderAuth | Write to Chatwoot (bot token) |
| `MySQL account` | mySql | All database operations |
| `Redis n8n` | redis | Message debounce queue + campaign cache |
| `database_chats` | postgres | AI agent chat memory |
| `Google Sheets account` | googleSheetsOAuth2Api | Product catalog lookup |
| `Agente Leads` | openAiApi | OpenAI o3-mini for Carlos agent |
| `chatgprsupricom@gmail.com` | gmailOAuth2 | Seller/admin email notifications |
| `WhatsApp account` | whatsAppApi | WhatsApp template alerts (phoneNumberId: 1082511111623191) |

## Working With These Files

Each `.json` file is a complete n8n workflow export. To modify a workflow:
1. Edit the JSON directly (node `parameters`, `conditions`, `jsCode` fields, etc.)
2. Import the updated file into the n8n instance via **Settings → Import workflow**

Node logic lives in `n8n-nodes-base.code` nodes as inline JavaScript in the `jsCode` parameter. The n8n expression syntax `={{ expression }}` is used for dynamic values in other node types.

The `id` field at the top level of each workflow JSON is the workflow's permanent n8n ID — do not change it.

## Key Business Rules Encoded in Workflows

- **Venezuelan phone normalization**: numbers starting with `0` → drop the `0` and prefix `58`; numbers starting with `4` → prefix `0`; always ensure format is `+58XXXXXXXXXX`
- **RIF normalization**: always stored as `J-XXXXXXXX` format
- **Seller assignment**: two separate stored procedures for Caracas/Carabobo (higher-volume region) vs. the rest of Venezuela
- **Carlos agent identity**: must never reveal it is an AI — enforced in the system prompt, not in code
- **Lead qualification gate**: only leads who confirm wholesale purchasing intent (`al_mayor == "Si"` on web form, or pass the agent's B2B qualification questions) are registered
