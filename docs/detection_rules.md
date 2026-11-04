# Detection Rules & Policy Reference — Black Box SIEM + EDR

This document covers the JSON schemas for process detection rules (`storage/rules.json`), global response policies (`storage/policies.json`), and endpoint firewall rules (`storage/firewall.json`) used by **Black Box**.

---

## 1. Process Detection Schema (`storage/rules.json`)

Rules are created in the SIEM operator console (`server (SIEM)/cli/agent-mgmt.sh`), synced to endpoints every 60 seconds via `agent (EDR)/core/sync.sh`, and evaluated locally by `agent (EDR)/core/detection-engine.sh`.

```json
{
  "process_rules": [
    {
      "name": "Interactive Reverse Shell",
      "match": "command_line",
      "value": "/bin/bash -i",
      "mitre": "T1059.004",
      "severity": "CRITICAL"
    },
    {
      "name": "Cron Persistence Edit",
      "match": "command_line",
      "value": "/var/spool/cron",
      "mitre": "T1053.003",
      "severity": "HIGH"
    },
    {
      "name": "SCP Lateral File Transfer",
      "match": "process_name",
      "value": "scp",
      "mitre": "T1570",
      "severity": "MEDIUM"
    }
  ]
}
```

### Rule Fields

| Field | Values | How `detection-engine.sh` Evaluates It |
| :--- | :--- | :--- |
| `name` | `String` | Alert identifier (`rule_id`) written to `alerts.log` and streamed to the SIEM |
| `match` | `process_name` \| `command_line` | Exact basename match on `.data.process_name` or substring `contains()` match on `.data.command_line` |
| `value` | `String` | Binary name (e.g., `ncat`, `nmap`, `scp`) or command-line pattern (e.g., `/bin/bash -i`, `base64 --decode`) |
| `mitre` | `String` | MITRE ATT&CK technique ID attached to the alert (`mitre_technique`) |
| `severity` | `LOW` \| `MEDIUM` \| `HIGH` \| `CRITICAL` | Alert severity; `CRITICAL` triggers active process termination when `edr_response` is enabled |

---

## 2. Deduplication & Active Response (`detection-engine.sh` + `response.sh`)

1. **Stream Filtering** — Tails `$ENDPOINT_LOG` and inspects `process_start` events containing a valid numeric PID.
2. **Cooldown Cache** — Tracks `alerted_pids[$pid]` and a 10-second per-rule timer (`last_alert_time[$rule_name]`) so noisy processes do not flood the SIEM.
3. **Alert Dispatch** — Appends a structured `process_detection` JSON record to `$ALERT_LOG` and streams a `CRITICAL` detection event to the SIEM over `socat TCP:9000`.
4. **Automated Process Termination (`Auto-Kill`)** — If `.global.edr_response == true` in `policies.json` and the matched rule has `severity == "CRITICAL"`, the engine invokes `core/response.sh "PROCESS" "$pid"`, which sends `SIGTERM` (`kill -15`), waits 1 second, and follows up with `SIGKILL` (`kill -9`) if the process is still alive.

---

## 3. Global Policy & Engine Tuning (`storage/policies.json`)

Managed live from `cli/dashboard.sh` (`Option 3: Policies`) and `cli/agent-mgmt.sh` (`Option 5: Engine Params`):

```json
{
  "global": {
    "edr_response": true,
    "firewall_enabled": false
  },
  "settings": {
    "watch_dirs": "/tmp /home /var/www /opt",
    "file_monitor_interval": 0.5,
    "max_hash_size_mb": 10,
    "hash_extensions": "sh py elf bin so jar exe run",
    "process_monitor_interval": 2,
    "file_event_ttl": 2,
    "file_hash_ttl": 300,
    "process_hash_ttl": 600,
    "network_event_ttl": 30
  }
}
```

---

## 4. Endpoint Firewall Rules (`storage/firewall.json`)

Managed from `cli/agent-mgmt.sh` (`Option 4: Firewall`) and enforced on endpoints by `agent (EDR)/core/firewall.sh` using dedicated `iptables` chains (`BLACKBOX-IN` and `BLACKBOX-OUT`). The console blocks any rule that would lock out the SIEM server IP or reserved ports (`9000`, `9100`, `22`).

```json
{
  "default_input": "ACCEPT",
  "default_output": "ACCEPT",
  "rules": [
    {
      "direction": "out",
      "action": "DROP",
      "port": "4444",
      "protocol": "tcp"
    }
  ]
}
```
