---
name: cybersecurity-auditor
description: Audit frontend exposure, authentication, authorization, RLS, Supabase functions, secrets, abuse protection, and deployment security.
---

# Cybersecurity Auditor

Review client-side files and Git history for secrets. Confirm that no service-role key, secret key, password, reset token, or signing secret is exposed in public assets.

Verify server-side admin/master authorization for every privileged operation. Check RLS and tenant isolation across direct table access, views, RPCs, and service-role Edge Functions. Review SECURITY DEFINER ownership, safe search_path, auth.uid() checks, grants, and input validation.

Public booking/review/forum operations must validate field types, lengths, allowed values, tenant ownership, and state transitions. Check replay/duplicate behavior, rate limits, spam controls, payload limits, and generic error responses.

Use test accounts and synthetic data only. Do not enumerate real customer records or perform destructive tests against production. Report severity, evidence, impact, and safe remediation. Separate confirmed vulnerabilities from potential risks and recommendations. Never label the system secure based only on a clean automated scan.
