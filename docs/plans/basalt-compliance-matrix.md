---
title: "Basalt Compliance & Security Matrix"
type: compliance
status: active
date: 2026-02-17
standards:
  - OWASP LLM Security Verification Standard (LLMSVS) Level 2
  - NIST SP 800-53 COSAiS (draft, monitoring)
---

# Basalt Compliance & Security Matrix

**PURPOSE**: Security sanity check during development. Track adherence to OWASP LLMSVS Level 2 and awareness of NIST SP 800-53 COSAiS.

**APPROACH**: MVP first. Document known gaps. Harden post-MVP.

**BIGGEST RISK**: Non-compliance with US federal AI cybersecurity standards and denied integration with federal information systems.

---

## Status Legend

| Status | Meaning |
|--------|---------|
| **IN-PLACE** | Inherently satisfied or implemented |
| **MVP-PARTIAL** | Partially addressed, needs hardening |
| **DEFERRED** | Post-MVP, planned for hardening phase |
| **N/A** | Not applicable to Basalt |

---

## Air-Gap Inherent Controls

Air-gapped deployment inherently mitigates:

| Threat | Why Mitigated |
|--------|--------------|
| Data exfiltration | No outbound network path |
| Remote model theft | No external access to endpoints |
| Runtime supply chain attacks | No downloads at runtime |
| Cloud credential leakage | No cloud APIs configured |
| Telemetry leakage | Disabled + no route exists |
| External prompt injection relay | No path to phone home |
| Model update tampering | Weights static on local disk |

**Air-gap does NOT mitigate**: Insider threats, supply chain during staging phase, local network lateral movement, Docker host privilege escalation, prompt injection effects within the isolated environment.

---

## OWASP Top 10 for LLM Applications

| # | Risk | Status | Components | Air-Gap Effect | Hardening Action |
|---|------|--------|-----------|---------------|-----------------|
| 01 | **Prompt Injection** | DEFERRED | vLLM, LiteLLM, Onyx, Open-WebUI | No exfiltration path. Injection still affects local outputs. | LiteLLM content filtering. Onyx system prompt protection. |
| 02 | **Insecure Output** | MVP-PARTIAL | Open-WebUI, Onyx | No external attack surface. | Verify framework output sanitization. No server-side execution of LLM output. |
| 03 | **Training Data Poisoning** | N/A | — | Inference only. No training/fine-tuning. | Verify model provenance + SafeTensor format during staging. |
| 04 | **Model DoS** | MVP-PARTIAL | vLLM, LiteLLM | Internal users only. | vLLM: `--max-model-len 4096`, `--max-num-seqs 128`, `--gpu-memory-utilization 0.80`. Add LiteLLM rate limits post-MVP. |
| 05 | **Supply Chain** | MVP-PARTIAL | All images, model weights | Attack surface limited to staging phase. | Pin image versions. SafeTensor format. Document SHAs. Artifact BOM. |
| 06 | **Info Disclosure** | DEFERRED | vLLM, Onyx (RAG), Open-WebUI | Data stays on network. Multi-clearance risk remains. | Onyx document ACLs. Authentik user access (Phase 6). Langfuse audit. |
| 07 | **Insecure Plugins** | MVP-PARTIAL | Onyx agents, connectors | No external APIs. Limited connectors. | Review agent permissions. Restrict connector scope. Log via Langfuse. |
| 08 | **Excessive Agency** | MVP-PARTIAL | Onyx agents | Blast radius = isolated network. | Read-only agents default. Human-in-the-loop for writes. |
| 09 | **Overreliance** | DEFERRED | Onyx, Open-WebUI | Same as any deployment. | System prompts for uncertainty. UI disclaimers. User training. |
| 10 | **Model Theft** | IN-PLACE | vLLM (weights on disk) | No exfiltration path. | File permissions. LiteLLM API auth. Authentik UI gate (Phase 6). |

---

## Infrastructure Security Controls

### Authentication & Authorization

| Control | MVP State | Hardening Target |
|---------|-----------|-----------------|
| vLLM API | None (internal only) | LiteLLM API keys gate all access |
| LiteLLM API | Master key | Per-user keys with rate limits |
| Langfuse | Init user (pk/sk keys) | Rotate keys, add users |
| Onyx | Disabled for dev | Enable, integrate Authentik OIDC |
| Open-WebUI | Local accounts | Integrate Authentik OIDC |
| **Centralized SSO** | **Not implemented** | **Authentik (Phase 6)** |

### Encryption

| Control | MVP State | Hardening Target |
|---------|-----------|-----------------|
| Postgres data at rest | Unencrypted | Docker volume or OS-level encryption |
| MinIO data at rest | Unencrypted | Server-side encryption |
| Model weights at rest | Unencrypted | OS-level disk encryption |
| Inter-service traffic | HTTP | TLS via Authentik reverse proxy |
| User-to-UI traffic | HTTP | HTTPS via Authentik reverse proxy |

### Credential Management

| Control | MVP State | Hardening Target |
|---------|-----------|-----------------|
| Database passwords | Default/weak | `openssl rand -hex 32` |
| API keys | Example values | Generate and rotate |
| Secrets storage | Plaintext .env | Restrict file permissions, Docker secrets |

### Logging & Monitoring

| Control | MVP State | Hardening Target |
|---------|-----------|-----------------|
| LLM request/response logging | Langfuse traces | **IN-PLACE** |
| Container logs | Docker json-file | Centralize, set retention |
| Access logs | Per-service defaults | Centralize via Authentik |
| Health monitoring | vLLM healthcheck only | All services |

---

## NIST SP 800-53 COSAiS

COSAiS (Control Overlays for Securing AI Systems) is in draft as of Feb 2026. Key applicable families: AC (Access Control), AU (Audit), CM (Configuration Mgmt), IA (Identification), SC (System Protection), SI (Info Integrity), SA (Supply Chain). Most overlap with OWASP controls tracked above. Will map specific controls as COSAiS is published.
