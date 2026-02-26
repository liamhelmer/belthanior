1. Debugging & Logging
Fail Fast, Log Everything: Default to running with debugging off, but use a persistent, unversioned local configuration file (e.g., .env.local) to toggle global debug flags.

Structured Logging: Exclusively use structured logging (e.g., JSON) with appropriate log levels (INFO, WARN, ERROR, DEBUG).

Graceful Error Handling: Ensure critical errors fail fast and halt execution, while non-critical errors are gracefully caught, logged, and bypassed.

Agentic Troubleshooting: Spawn a specialized troubleshooting subagent for errors. Task this agent strictly with identifying the root cause and outputting a diagnosis, not executing the fix.

2. Testing
Behavior-Driven Validation: Prioritize tests that validate the actual user experience and expected results over purely synthetic unit tests.

Immutable Testing: Never disable or alter existing tests to force a build to pass. Tests must only be updated if the underlying business logic or feature requirements have intentionally changed.

Pre-Commit E2E: End-to-End tests must pass successfully before any code is committed or merged to the main branch.

3. Orchestration: Subagents & Teams
Context Preservation: Offload long-running operations (waiting for deployments, tailing logs, data parsing) to specialized subagents to keep the primary agent's context window clean.

Role-Based Prompting: For complex features, deploy an agent team. Each agent must receive a specific role prompt and only the exact details from the current plan relevant to their specific task.

Shared Path: Always pass the execution path of the current plan to any agent or team involved in its execution to maintain global alignment.

4. Planning & Brainstorming
Zero Ambiguity: Launch brainstorming or clarifying skills whenever a plan lacks detail. Do not write code until the user's request is entirely unambiguous.

Human-in-the-Loop (HITL) Gates: Write concrete plans for all complex features or fixes to a /plans directory. Require explicit user approval via chat or Pull Request before execution begins.

Plan Documents: always write out plans into a document in /docs/plans

ADR Documents: technical, architectural and other design decisions should be recorded in /docs/adrs

5. Research & Dependencies
Pragmatic Reuse: Prioritize existing open-source projects with permissive licenses over custom builds. Always research the latest stable versions and API standards before finalizing a plan.

Objective Evaluation: Evaluate third-party dependencies based on recent commit activity, security posture, and community adoption before integration.

Lightweight First: Default to small, fast, and modular libraries. Only adopt large, complex frameworks if their specific advanced features are strictly required.

6. Security & Secrets
Zero Hardcoding: Never log, hardcode, or transmit secrets. Agents must strictly use environment variables or secret managers for credentials.

Sanitization: Scrub all log outputs, CLI commands, and Pull Requests for potential API keys or tokens before writing or transmitting them.

7. Execution & State Management
Idempotency: Write idempotent scripts and functions. If an agent's script fails halfway through, running it a second time must not break the system or create duplicate resources.

Circuit Breakers: Establish strict failure thresholds. If an agent or subagent fails to compile code, fails a test, or errors out on the exact same task three times in a row, it must immediately halt and escalate to the user with a summary of the failed attempts to prevent infinite loops.

8. Version Control & Commits
Atomic Commits: Make atomic, descriptive commits. Agents must not dump dozens of unassociated files into a single massive commit.

Conventional Messaging: Commit code in small, logical, revertible chunks using descriptive conventional commit messages (e.g., feat:, fix:, refactor:).

9. Coding & Architecture
Modular & DRY: Build small, reusable modules. Always check the existing codebase for equivalent functions before generating new ones.

Facade Pattern for Externals: Wrap all external library and API calls in local functions or modules to prevent vendor lock-in and allow future swapping.

Manifest Maintenance: Record the creation, purpose, and location of every new function or module in an MANIFEST.md (or similar manifest) file to prevent duplication of effort by future agents.

----------------MANIFEST.md------------------
# Agent & Module Manifest

**Purpose:** This file acts as the single source of truth for all coding agents. It records the existing agents, available internal modules, and external integrations to prevent duplication of effort and maintain architectural consistency. 
**Rule:** Agents MUST update this registry whenever a new reusable module, agent role, or external facade is created.

---

## 🤖 1. Active Agent Teams & Roles
*Defines the specialized subagents currently configured for this project to prevent spawning redundant agents.*

| Agent Name | Primary Role | Trigger Condition | Capabilities / Scopes |
| :--- | :--- | :--- | :--- |
| `Planner_Agent` | Breaks down user requests into architectural plans. | Ambiguous prompts or new feature requests. | Read/Write `/plans`, access to project root. |
| `GCP_Infra_Agent` | Handles platform engineering and infrastructure provisioning. | Terraform/GCP state changes required. | Read/Write `/infra`, GCP API access. |
| `Troubleshooter` | Diagnoses pipeline or code execution failures. | Non-zero exit codes, E2E test failures. | Read-only access to logs and codebase. |

---

## 🧩 2. Module & Function Registry
*A directory of small, reusable modules. Always check here before writing a new utility function.*

| Module / Function | File Path | Description | Dependencies | Idempotent (Y/N) |
| :--- | :--- | :--- | :--- | :--- |
| `logger.setup()` | `src/utils/logger.py` | Configures structured JSON logging with dynamic levels based on `.env.local`. | `logging`, `json` | Y |
| `device_sync_state()` | `src/core/sync.py` | Synchronizes execution state across multiple device nodes. | None | Y |
| `parse_matrix_event()` | `src/api/matrix.py` | Parses incoming JSON payloads from the Matrix protocol into standard data classes. | `dataclasses` | Y |

---

## 🔌 3. External Integrations (Facades)
*Registry of wrapped external libraries and APIs. Never call external libraries directly; use these facades.*

| Facade Name | File Path | Wrapped Library/API | Purpose |
| :--- | :--- | :--- | :--- |
| `CloudStorageService` | `src/facades/storage.py` | `google-cloud-storage` | Wraps bucket upload/download logic to prevent vendor lock-in. |
| `AuthWrapper` | `src/facades/auth.py` | `OAuth2` | Standardizes token validation across all distributed agents. |

---

## 📝 4. Global State & Conventions
* **Log Location:** `/var/log/agents/` (Structured JSON only).
* **Debug Flag:** Set `AGENT_DEBUG=true` in `.env.local` (Never commit this file).
* **Max Retries:** 3 attempts per subagent before circuit breaker triggers and escalates to user.
