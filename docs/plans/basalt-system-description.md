# Basalt AI Concept: Technical Documentation

**PURPOSE** Overview of Basalt architecture for on-prem inferencing, document and code assistance, and smart document search for restricted isolated US federal information systems.

## Introduction

Basalt will eventually be subject to NIST AI standards and controls in accordance with SP 800-53 Control Overlays for Securing AI Systems (COSAiS). Federal AI risk management framework (RMF) standards are in the drafting phase and are continuously developing. Security will be top of mind during development.

**BIGGEST BASALT RISK** Non-compliance with US federal AI cybersecurity standards and denied integration with federal information systems

**KEY LAYERS**
- User Interface: Manages user login, controls access to supported applications, tracks usage metrics
- Core Intelligence: Provides the assistant interfaces and ingests proprietary or critical information
- Inference Service: Load balancing API server for efficient model inferencing

| Layer | Services |
|-------|----------|
| User Interface | Authentik (SSO/reverse proxy), Open-WebUI, Onyx web UI |
| Core Intelligence | Onyx (RAG, agents, connectors), Open-WebUI (chat) |
| Inference Service | LiteLLM (proxy/load balancer), vLLM (GPU model serving), Langfuse (observability) |

## User Flow

**BASALT USER FLOW**
User logs into Authentik unified interface dashboard, which functions as a reverse proxy. Select an AI assistant application: Open-WebUI or Onyx. Both communicate with the LiteLLM AI proxy server which load balances across instances of vLLM model inferencing service.

## Basalt LLM Implementation

vLLM serves as the inference backend using local GPU to serve LLM results via an OpenAI-compatible API server. The MVP LLM is gpt-oss:20b. gpt-oss:120b is a future scaling target requiring multi-GPU hardware.

**SECURITY NOTE** Model weights are loaded via the SafeTensor format to mitigate remote code execution threats.

## OWASP LLM Security Verification

**PURPOSE** Demonstrate as much adherence to *LLMSVS Level 2 - Moderate Security* requirements defined in the OWASP LLM Security Verification Standard (https://github.com/OWASP/www-project-llm-verification-standard/files/14193569/OWASP_Large_Language_Model_Security_Verification_Standard-0.1_en.pdf). We will aim for Level 2 adherence while prioritizing quality of service. There are many controls that are not applicable to Basalt due to being fully self-hosted with no internet access and not hosting training or finetuning services.
