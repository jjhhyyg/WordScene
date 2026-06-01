# WordScene Scripts

Keep `scripts/` as the public command surface. Everything under
`scripts/internal/` is implementation detail, regression coverage, or a
specialized helper used by the public entry points.

## Public Entry Points

Run these from the repository root:

```bash
scripts/test_verify_release_readiness.sh
scripts/run_release_candidate_gate.sh --allow-provisioning-updates --platform all
scripts/run_live_deepseek_translation_smoke.sh --evidence docs/release-smoke-evidence.md
scripts/manual_smoke_session_guide.sh
scripts/check_release_completion.sh
```

## Internal Scripts

`scripts/internal/` contains build helpers, evidence writers, signing
diagnostics, localization/privacy checks, manual smoke subcommands, and shell
regression tests. Prefer the public entry points above unless you are debugging
one specific release step.
