# cisco-secure-access-rc-deploy

Deploy a **Cisco Secure Access Resource Connector** on **Ubuntu 22.04 LTS** (Docker host).

## Preparation

### Secure Access (before SSH to the RC VM)

1. Create a **Resource Connector Group** (name and region).
2. Copy the **Provisioning Key** (connector group → **View Provisioning Key**).
3. The key binds the connector to that group — you do **not** enter the group name on the host.

You will need at deploy time:

| Input | Source |
|---|---|
| **Connector name** | Your choice (1–40 chars: letters, digits, `-`, `_`) — e.g. `rc-01` |
| **Provisioning key** | Step 2 above |

After `./deploy.sh` finishes: **Confirm** the connector in the dashboard, then **Enable** it.

### Host requirements

| Item | Detail |
|---|---|
| OS | Ubuntu Server **22.04 LTS** x64 (dedicated RC host) |
| CPU / RAM / disk | ≥ 2 vCPU, ≥ 4 GB RAM, ≥ 8 GB disk (Cisco minimum) |
| Privilege | `sudo` |
| Docker | **Do not** pre-install Docker (especially not Snap). Cisco's script installs Docker from apt. |
| Egress | Outbound HTTPS to Secure Access, Sigstore, GitHub (during setup). See [Allow Resource Connector traffic](https://docs.sse.cisco.com/sse-user-guide/docs/allow-resource-connector-traffic-to-secure-access). |

## Deploy

```bash
git clone https://github.com/Chir0rin/cisco-secure-access-rc-deploy.git
cd cisco-secure-access-rc-deploy
./deploy.sh
```

The script prompts for **connector name** and **provisioning key**, then installs and launches the connector. Approve `sudo` when prompted.

**Automation (optional)** — skip prompts for CI or cloud-init:

```bash
sudo RC_NAME=rc-01 RC_PROVISIONING_KEY='<key>' ./deploy.sh
```

| Variable | Meaning |
|---|---|
| `RC_NAME` | Connector name |
| `RC_PROVISIONING_KEY` | Provisioning key from the dashboard |
| `RC_SETUP_URL` | Default: `https://us.repo.acgw.sse.cisco.com/scripts/latest/setup_connector.sh` |

## Uninstall

Remove the connector from **Secure Access first**, then clean up the host.

### Dashboard

1. **Connect → Network Connections → Connector Groups**
2. Open the group → **Connectors** tab
3. **Disable** (optional, recommended before delete)
4. **Revoke** or **Delete** the connector

### Host

```bash
sudo /opt/connector/install/connector.sh stop --destroy
sudo docker ps    # should show no RC container
```

Full cleanup (reinstall or decommission):

```bash
sudo rm -rf /opt/connector
```

Optional: remove Docker images if this host runs no other containers; remove the git clone.

To redeploy: repeat **Deploy** with a new or regenerated provisioning key.

## What this does

This repo is a thin wrapper around Cisco's official Docker install flow. It does **not** replace dashboard steps (Confirm / Enable) or ZTA policy configuration.

| Step | Action |
|---|---|
| 1 | Preflight (Ubuntu version, sudo, `dpkg` state, Snap Docker warning) |
| 2 | Download Cisco `setup_connector.sh` (skipped if `/opt/connector/install/connector.sh` exists) |
| 3 | Run `setup_connector.sh` (Docker via apt + `/opt/connector`) |
| 4 | Run `connector.sh launch --name … --key …` |
| 5 | Print post-deploy dashboard reminders |

## References

### Cisco documentation

- [Deploy a Resource Connector in Docker (SSE user guide)](https://docs.sse.cisco.com/sse-user-guide/docs/deploy-a-resource-connector-in-docker)
- [Deploy a Connector in Docker (SecureDocs)](https://securitydocs.cisco.com/docs/csa/olh/120695.dita)
- [Disable, Revoke, or Delete a Connector](https://securitydocs.cisco.com/docs/csa/olh/120705.dita)
- [Stop the Container / Delete the Container](https://securitydocs.cisco.com/docs/csa/olh/120727.dita)
- [Stop a Connector](https://securitydocs.cisco.com/docs/csa/olh/120792.dita)
- [Cisco TAC: stop --destroy and remove `/opt/connector`](https://www.cisco.com/c/en/us/support/docs/security/security-connector/225492-troubleshoot-secure-access-resource.html)

### Troubleshooting

| Symptom | Check |
|---|---|
| Docker install fails | `sudo dpkg --configure -a`; remove Snap Docker; retry |
| GPG / cosign errors during setup | NTP; egress to GitHub and `tuf-repo-cdn.sigstore.dev` |
| Connector in dashboard but no traffic | **Enable** in dashboard; ZTA profile and access rules |
| Wrong connector group | Regenerate key from the intended group; redeploy |

### License

MIT — see [LICENSE](LICENSE). Cisco Secure Access software and images are subject to Cisco terms; this repo only wraps Cisco-published install scripts.
