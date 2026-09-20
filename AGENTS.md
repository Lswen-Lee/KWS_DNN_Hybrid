# Repository workflow requested by the owner

- Confirmed repository: `Lswen-Lee/KWS_DNN_Hybrid`, private. Use Git HTTPS credentials verified as `Lswen-Lee`; do not use another account's connector to publish elsewhere. Commit author uses the existing `Lswen-Lee` Git identity.

- After completing an authorized implementation/change, run relevant verification and update the corresponding architecture/test documentation.
- Create a focused Git commit for completed work and push it to the confirmed GitHub remote when authentication/network access is available. Commit and push each completed system-level integration/verification milestone.
- Never force-push, rewrite existing history, or include unrelated user changes without permission.
- Never commit secrets, credentials, full Vivado/simulation build trees, or large generated binaries. Review the staged diff and file list first.
- Do not label unrun/failed verification as passing. Report commit hash, branch, verification status, and whether push actually succeeded.
- If repository owner/visibility, remote, author identity, or authentication is missing/ambiguous, ask the user. Never invent credentials or an author identity.
- Read-only analysis alone does not require an empty commit. This workflow applies while actively working in this repository; it does not imply unattended background monitoring.
