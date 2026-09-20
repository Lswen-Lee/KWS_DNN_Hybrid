# Repository workflow requested by the owner

- Confirmed repository: `Lswen-Lee/KWS_DNN_Hybrid`, private. Use Git HTTPS credentials verified as `Lswen-Lee`; do not use another account's connector to publish elsewhere. Commit author uses the existing `Lswen-Lee` Git identity.

- After completing an authorized implementation/change, run relevant verification and update the corresponding architecture/test documentation.
- Create a focused Git commit for completed work and push it to the confirmed GitHub remote when authentication/network access is available. Commit and push each completed system-level integration/verification milestone.
- Never force-push, rewrite existing history, or include unrelated user changes without permission.
- Never commit secrets, credentials, full Vivado/simulation build trees, or large generated binaries. Review the staged diff and file list first.
- Do not label unrun/failed verification as passing. Report commit hash, branch, verification status, and whether push actually succeeded.
- If repository owner/visibility, remote, author identity, or authentication is missing/ambiguous, ask the user. Never invent credentials or an author identity.
- Read-only analysis alone does not require an empty commit. This workflow applies while actively working in this repository; it does not imply unattended background monitoring.

## Commit message convention

- Use Conventional Commits: `type(scope): concise description`.
- Types: `feat` (new capability), `fix` (bug fix), `refactor` (behavior-preserving restructuring), `perf` (performance improvement), `test` (verification), `docs` (documentation), `build` (build/tool flow), `ci` (automation), `chore` (maintenance), `revert` (reversal).
- Use a meaningful scope, such as `pe9`, `pe8`, `dcim`, `engine`, `board`, `vivado`, `verification`, or `repo`. Use Traditional Chinese descriptions/body for readability; keep type/scope identifiers in English.
- Describe the concrete change; do not use vague subjects such as "update", "修改", or "完成" alone. Keep commits focused; do not relabel unmeasured improvements as proven performance gains.
- After a blank line, include a body explaining: 修改內容 (what changed), 原因 (why), 驗證 (commands/results, or explicitly not run), and 影響 (interface/timing/resource implications or limitations when relevant).
- For breaking interface/protocol changes, use `type(scope)!: description` and a `BREAKING CHANGE:` footer describing migration requirements.
- Distinguish simulation, lint, Tcl mock tests, Vivado synthesis/implementation, and board tests; never claim one implies another passed.
- Apply this convention to future commits. Do not rewrite previously pushed history solely to change message style.

Example:

```text
fix(vivado): 將板級 XDC 檢查移至 Tcl hook

修改內容：移除 XDC 的 if，新增時脈與同步器檢查。
原因：Vivado 的 XDC reader 不支援該條件判斷。
驗證：Tcl mock 測試通過；尚未執行 Windows Vivado。
影響：不修改 RTL 與 125 MHz 時序目標。
```
