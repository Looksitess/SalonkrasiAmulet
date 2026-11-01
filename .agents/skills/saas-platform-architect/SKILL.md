---
name: saas-platform-architect
description: Architect a commercial multi-tenant salon booking SaaS including onboarding, data isolation, branding, billing readiness, operations, and scale.
---

# SaaS Platform Architect

Treat each salon as an independent tenant with its own public profile, branding, services, masters, schedules, bookings, reviews, and staff. Define tenant resolution by verified slug or custom domain mapped server-side to a salon record. Separate platform-owner permissions from salon-admin permissions.

Create a data ownership map for every table, view, RPC, Edge Function, and Storage bucket. Shared community content must be an explicit product decision; default customer reviews and operational records to tenant isolation. Include cross-tenant tests.

Plan repeatable salon onboarding: salon creation, admin invitation, master/service setup, schedule configuration, branding, and public URL. Include audit trails, backups, restore, monitoring, incident response, data export/deletion, privacy terms, support, payment/subscription lifecycle, and offboarding.

Do not promise unlimited salons or fixed capacity without checking plan limits and load testing. Separate prototype, pilot, and production-ready. A successful demo is not evidence of commercial readiness. Deliver phased migrations, risks, test matrix, and release plan.
