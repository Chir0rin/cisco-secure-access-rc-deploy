# cisco-secure-access-rc-deploy

Deploy a **Cisco Secure Access Resource Connector** on **Ubuntu 22.04 LTS** (Docker host).

Clone this repo on the RC VM, run one script, enter **connector name** and **provisioning key** — the wrapper downloads Cisco's official `setup_connector.sh`, installs the connector stack, and launches the container.

## Before you start (Secure Access UI)

1. Create a **Resource Connector Group** (name + region).
2. Open **View Provisioning Key** for that group and copy the key.
3. The key binds the connector to that group — you do **not** pass the group name on the host.

Official guide: [Deploy a Resource Connector in Docker](https://docs.sse.cisco.com/sse-user-guide/docs/deploy-a-resource-connector-in-docker)

After deployment, in the dashboard: **Confirm** the connector, then **Enable** it.

## Requirements

| Item | Detail |
|---|---|
| OS | Ubuntu Server **22.04 LTS** x64 (dedicated RC host) |
| CPU / RAM / disk | ≥ 2 vCPU, ≥ 4 GB RAM, ≥ 8 GB disk (Cisco minimum) |
| Privilege | `sudo` |
| Docker | **Do not** pre-install Docker (especially not Snap). Cisco's script installs Docker from apt. |
| Egress | Outbound HTTPS to Secure Access, Sigstore, GitHub (during setup). See [Allow Resource Connector traffic](https://docs.sse.cisco.com/sse-user-guide/docs/allow-resource-connector-traffic-to-secure-access). |

## Quick start

```bash
git clone https://github.com/Chir0rin/cisco-secure-access-rc-deploy.git
cd cisco-secure-access-rc-deploy
chmod +x deploy.sh
./deploy.sh
```

You will be prompted for:

- **Connector name** — 1–40 characters: letters, digits, `-`, `_`
- **Provisioning key** — from the connector group's **View Provisioning Key**

## Non-interactive (automation)

```bash
export RC_NAME="dmzaas-rc-01"
export RC_PROVISIONING_KEY="<provisioning-key-from-dashboard>"
sudo -E ./deploy.sh
```

Optional:

| Variable | Default |
|---|---|
| `RC_SETUP_URL` | `https://us.repo.acgw.sse.cisco.com/scripts/latest/setup_connector.sh` |

## What the script does

1. Preflight (Ubuntu version, sudo, pending `dpkg` config, Snap Docker warning)
2. Download Cisco `setup_connector.sh` (unless `/opt/connector/install/connector.sh` already exists)
3. Run `sudo ./setup_connector.sh`
4. Run `sudo /opt/connector/install/connector.sh launch --name … --key …`
5. Print dashboard follow-up (Confirm / Enable)

## Troubleshooting

| Symptom | Check |
|---|---|
| Docker install fails | Run `sudo dpkg --configure -a`, remove Snap Docker, retry |
| GPG / cosign errors during setup | Host clock (NTP), egress to GitHub + `tuf-repo-cdn.sigstore.dev` |
| Connector shows up but no traffic | Dashboard **Enable**; ZTA profile / access rules (outside this repo) |
| Wrong group | Regenerate key from the intended RCG and redeploy |

## References

- [Deploy a Connector in Docker (SecureDocs)](https://securitydocs.cisco.com/docs/csa/olh/120695.dita)
- [Resource Connector knowledge (internal lab notes)](https://docs.sse.cisco.com/sse-user-guide/docs/deploy-a-resource-connector-in-docker)

## License

MIT — see [LICENSE](LICENSE). Cisco Secure Access software and images are subject to Cisco terms; this repo only wraps Cisco-published install scripts.
