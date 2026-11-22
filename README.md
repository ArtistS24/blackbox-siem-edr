<div align="center">

<img src="assets/hero_banner.svg" width="100%" alt="Black Box — Autonomous SIEM Server &amp; Endpoint EDR" />

<br/>

[![Language](https://img.shields.io/badge/Language-GNU_Bash-d4a359?style=for-the-badge&logo=gnubash&logoColor=white&labelColor=06090e)](server%20%28SIEM%29/SIEM.sh)
[![Telemetry](https://img.shields.io/badge/Transport-socat_%2B_jq-0e7490?style=for-the-badge&logo=linux&logoColor=white&labelColor=06090e)](server%20%28SIEM%29/core/ingest.sh)
[![Endpoint Sensor](https://img.shields.io/badge/Sensor-inotifywait_%2B_%2Fproc-6366f1?style=for-the-badge&logo=kalilinux&logoColor=white&labelColor=06090e)](agent%20%28EDR%29/agent/agent.sh)
[![Rule Spec](https://img.shields.io/badge/Rules_%26_Policies-JSON_Spec-b45309?style=for-the-badge&logo=json&logoColor=white&labelColor=06090e)](docs/detection_rules.md)
[![SOC Dossier](https://img.shields.io/badge/SOC_Dossier-PDF_(12_Pages)-56d364?style=for-the-badge&logo=readthedocs&logoColor=white&labelColor=06090e)](docs/Blackbox_SIEM_EDR_Portfolio.pdf)
[![Accreditation](https://img.shields.io/badge/Accreditation-NX220_SOC_Analyst-0284c7?style=for-the-badge&logo=openbadges&logoColor=white&labelColor=06090e)](docs/NX220_SOC_Analyst_Accreditation.pdf)

</div>

<p align="center">
  <img src="assets/pipeline.svg" width="100%" alt="Black Box 4-Stage SIEM + EDR Architecture" />
</p>

<p align="center">
  <img src="assets/sec_1_capabilities.svg" alt="I · Autonomous SIEM Ingestion &amp; Event Correlation" width="100%" />
  <img src="assets/panel_1_capabilities.svg" alt="Black Box Core SIEM &amp; EDR Capabilities" width="100%" />
</p>

<p align="center">
  <img src="assets/sec_2_modules.svg" alt="II · Endpoint EDR Telemetry &amp; Procfs Sensor Matrix" width="100%" />
  <img src="assets/panel_2_modules.svg" alt="Black Box Subsystem &amp; Sensor Matrix" width="100%" />
</p>

<p align="center">
  <img src="assets/sec_3_walkthrough.svg" alt="III · Active Remediation &amp; MITRE Defense Execution" width="100%" />
  <a href="docs/Blackbox_SIEM_EDR_Portfolio.pdf" title="Open Black Box Technical Portfolio Dossier (12-Page PDF)"><img src="assets/evidence/poc_plate_1_siem_dashboard_and_fleet.png" alt="PoC Plate 1 — Live SOC Console, Telemetry Sparkline Trend, JSON Field Discovery &amp; Fleet Monitor" width="100%" /></a>
  <a href="docs/Blackbox_SIEM_EDR_Portfolio.pdf" title="Open Black Box Technical Portfolio Dossier (12-Page PDF)"><img src="assets/evidence/poc_plate_2_edr_sensor_and_remediation.png" alt="PoC Plate 2 — Multi-Source EDR Telemetry, Inotify Sensor, Automated SIGKILL Remediation &amp; Dynamic Host Isolation" width="100%" /></a>
</p>

<p align="center">
  <img src="assets/sec_4_execution.svg" alt="IV · Fleet Policy Distribution &amp; ATT&amp;CK Rules Spec" width="100%" />
</p>

```bash
# 1. Launch Central SIEM Server (TCP:9000 Ingest, Parser, HTTP:9100 Sync & Live SOC TUI)
git clone https://github.com/ArtistS24/blackbox-siem-edr.git
cd "blackbox-siem-edr/server (SIEM)"
chmod +x SIEM.sh cli/*.sh core/*.sh engine/*.sh
sudo ./SIEM.sh

# 2. Enroll or Launch Linux Endpoint EDR Agent
cd "../agent (EDR)"
chmod +x core/*.sh agent/*.sh
sudo ./core/Main.sh
```

<p align="center">
  <img src="assets/panel_3_workspace.svg" alt="Black Box SIEM Server &amp; Endpoint EDR Workspace Hierarchy" width="100%" />
</p>

<div align="center">

[![socat](https://img.shields.io/badge/Transport-socat_TCP%3A9000-0d131c?style=flat-square&logo=linux&logoColor=818cf8&labelColor=06090e)](http://www.dest-unreach.org/socat/)
[![jq](https://img.shields.io/badge/Parser-jqlang%2Fjq-0d131c?style=flat-square&logo=json&logoColor=38bdf8&labelColor=06090e)](https://github.com/jqlang/jq)
[![inotify-tools](https://img.shields.io/badge/Sensor-inotify--tools-0d131c?style=flat-square&logo=linux&logoColor=34d399&labelColor=06090e)](https://github.com/inotify-tools/inotify-tools)
[![MITRE ATT&CK](https://img.shields.io/badge/Detection-MITRE_ATT%26CK-0d131c?style=flat-square&logo=target&logoColor=f43f5e&labelColor=06090e)](https://attack.mitre.org/)
[![iptables](https://img.shields.io/badge/Isolation-Linux_iptables-0d131c?style=flat-square&logo=linux&logoColor=c084fc&labelColor=06090e)](https://www.netfilter.org/)

</div>
