# CLI reference

Use only these supported secret-execution paths:

Resolve `envstore` from `PATH` first. If it is unavailable, use `$HOME/.local/bin/envstore`. The examples below use `envstore` as shorthand for that resolved executable.

```text
envstore doctor [--json]
envstore context [--json]
envstore run [--set NAME] -- EXECUTABLE [ARG...]
envstore profile run NAME
envstore grant request --profile NAME [--ttl 5m] [--uses 1] [--wait]
envstore grant request [--set NAME] [--ttl 5m] [--uses 1] -- EXECUTABLE [ARG...]
envstore grant list [--json]
envstore grant revoke UUID
```

Durations accept seconds, minutes, or hours, such as `30s`, `5m`, and `1h`. Keep grants at one use unless repeated execution is necessary. Keep TTL at five minutes or less unless the user requests otherwise.

`--json` returns protocol-versioned metadata and stable error codes. It never returns environment values. Child stdout and stderr pass through unchanged and may still contain sensitive application output; summarize cautiously.
