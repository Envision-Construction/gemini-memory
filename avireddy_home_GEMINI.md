# Gemini Code Analysis: Envision OS

This document provides a comprehensive analysis of the "Envision OS" project and the user's development environment, to be used as instructional context for future interactions.

## Project Overview

The current directory contains the "Envision OS" project, a multi-channel messaging bot for Construction Project Intelligence. It is a FastAPI application that connects to a central "Envision-MCP" gateway.

**Key Features:**

*   **Multi-channel messaging:** Supports Slack, Telegram, WhatsApp, Discord, and Signal.
*   **Single-brain architecture:** All intelligence (tool routing, Gemini orchestration, RAG) is handled by the Envision-MCP gateway. This service is a thin client that handles channel I/O, ACL gating, and response formatting.
*   **Observability:** The project is instrumented with OpenTelemetry for tracing and Cloud Monitoring for metrics.
*   **Security:** The application uses hardened, distroless Docker images for production and includes robust security practices like Slack request signature verification.

## Building and Running

### Local Development

To run the project locally, use the following commands:

```bash
# Install dependencies
uv venv && source .venv/bin/activate && uv sync

# Set environment variables
export GOOGLE_CLOUD_PROJECT=claude-mcp-457317
export CONTEXT_PROJECT_ID=claude-mcp-457317
export ENVISION_MCP_URL=<mcp-gateway-url>

# Run locally
python main.py

# Run tests
pytest tests/ -v

# Format
black . && ruff check . --fix
```

### Deployment

Deployments are handled automatically via Cloud Build when code is pushed to the `main` branch. The service is deployed to Cloud Run in the `claude-mcp-457317` GCP project.

## Development Conventions

*   The project uses `uv` for Python package management.
*   Code formatting is enforced with `black` and `ruff`.
*   The application is containerized using a two-stage `Dockerfile` for a lean and secure production environment.
*   The project is well-documented with a detailed `README.md` and inline comments.
*   API keys and other secrets are loaded from the environment or macOS Keychain, not hardcoded.

## User's Development Environment

The user's development environment is configured in the `.zshrc` file and reveals several important details:

*   **Python:** The user is using Python 3.13 installed via Homebrew.
*   **GCP:** The default GCP project is `gen-lang-client-0331443493`, but has been changed to `claude-mcp-457317` in the current session.
*   **Project Shortcuts:** The user has several shell aliases for quickly navigating to related projects in the `~/GitHub/` directory and launching a tool called `claude`.
    *   `ccc`: `cd ~/GitHub/central-command`
    *   `cce`: `cd ~/GitHub/Envision-MCP`
    *   `ccs`: `cd ~/GitHub/Envision-OS-slackwrapper`
    *   `ccm`: `cd ~/GitHub/claude-code-memory` (Claude Code config — separate from Gemini)
*   **Other Tools:** The user has `docker` and `bun` installed.

## Note on Directory Structure

The "Envision OS" project is currently located in the user's home directory (`/Users/avireddy`). This is unconventional. The user's `.zshrc` file contains a shortcut, `ccs`, that suggests the project is intended to be in `~/GitHub/Envision-OS-slackwrapper`. For any file-based operations, it's important to confirm the correct path with the user.
