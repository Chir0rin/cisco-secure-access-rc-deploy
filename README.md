# cisco-secure-access-rc-deploy

Deploy a **Cisco Secure Access Resource Connector** on **Ubuntu 22.04 LTS** (Docker host).

Clone this repo on the RC VM and run `./deploy.sh`. The script asks for everything it needs on the host — no environment variables required for a normal install.

## What you need

| # | Item | Where |
|---|---|---|
| 1 | **Connector name** | You choose (1–40 chars: letters, digits, `-`, `_`) — e.g. `rc-01` |
| 2 | **Provisioning key** | Secure Access → connector group → **View Provisioning Key** |

Prepare the key in the dashboard **before** running the script. The key already ties the connector to that **Resource Connector Group** — you do not enter the group name on the host.

After deployment: **Confirm** the connector in the dashboard, then **Enable** it.

Official guide: [Deploy a Resource Connector in Docker](https://docs.sse.cisco.com/sse-user-guide/docs/deploy-a-resource-connector-in-docker)

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
./deploy.sh
```

The script prompts for **connector name** and **provisioning key**, then runs Cisco's install and launch steps. Use `sudo` when asked (or run as root).

## Automation (optional)

To skip prompts (CI, cloud-init, etc.), set:

| Variable | Meaning |
|---|---|
| `RC_NAME` | Connector name |
| `RC_PROVISIONING_KEY` | Provisioning key from the dashboard |

```bash
sudo RC_NAME=rc-01 RC_PROVISIONING_KEY='<key>' ./deploy.sh
```

Advanced:

| Variable | Default |
|---|---|
| `RC_SETUP_URL` | `https://us.repo.acgw.sse.cisco.com/scripts/latest/setup_connector.sh` |

## What the script does

1. Preflight (Ubuntu version, sudo, pending `dpkg` config, Snap Docker warning)
2. Download Cisco `setup_connector.sh` (unless `/opt/connector/install/connector.sh` already exists)
3. Run `sudo ./setup_connector.sh`
4. Run `sudo /opt/connector/install/connector.sh launch --name … --key …`
5. Print dashboard follow-up (Confirm / Enable)

## Uninstall

Remove the connector from **Secure Access first**, then tear down the Docker host. Reversing the order can leave orphaned dashboard entries or a host that still runs containers.

### 1. Secure Access dashboard

1. **Connect → Network Connections → Connector Groups**
2. Open the connector group → **Connectors** tab
3. **Disable** the connector (stops forwarding; optional but recommended before delete)
4. **Revoke** or **Delete** the connector in the dashboard

Docs: [Disable, Revoke, or Delete a Connector](https://securitydocs.cisco.com/docs/csa/olh/120705.dita)

### 2. On the Ubuntu host

Stop the container and remove local connector state (replace `<connector_name>` if your install used a specific name):

```bash
sudo /opt/connector/install/connector.sh stop --destroy
```

Verify nothing is running:

```bash
sudo docker ps
```

### 3. Full local cleanup (reinstall or decommission)

Remove Cisco install files under `/opt/connector`:

```bash
sudo rm -rf /opt/connector
```

Optional — remove leftover Docker images (only if you are not running other containers on this host):

```bash
sudo docker image ls
sudo docker image rm ciscosecure/resource-connector:<tag>   # if listed
```

Optional — remove this repo clone:

```bash
cd ..
rm -rf cisco-secure-access-rc-deploy
```

### 4. Redeploy on the same VM

After uninstall steps 1–3, clone this repo again and run `./deploy.sh` with a **new or regenerated provisioning key** from the target connector group.

### Uninstall references

- [Stop the Container / Delete the Container (Docker)](https://securitydocs.cisco.com/docs/csa/olh/120727.dita)
- [Stop a Connector](https://securitydocs.cisco.com/docs/csa/olh/120792.dita)
- [Disable, Revoke, or Delete Resource Connectors and Groups](https://securitydocs.cisco.com/docs/csa/olh/120706.dita)
- [Cisco TAC: stop --destroy and remove `/opt/connector`](https://www.cisco.com/c/en/us/support/docs/security/security-connector/225492-troubleshoot-secure-access-resource.html)

## Troubleshooting

| Symptom | Check |
|---|---|
| Docker install fails | Run `sudo dpkg --configure -a`, remove Snap Docker, retry |
| GPG / cosign errors during setup | Host clock (NTP), egress to GitHub + `tuf-repo-cdn.sigstore.dev` |
| Connector shows up but no traffic | Dashboard **Enable**; ZTA profile / access rules (outside this repo) |
| Wrong group | Regenerate key from the intended RCG and redeploy |

## References

- [Deploy a Connector in Docker (SecureDocs)](https://securitydocs.cisco.com/docs/csa/olh/120695.dita)
- [Deploy a Resource Connector in Docker (SSE user guide)](https://docs.sse.cisco.com/sse-user-guide/docs/deploy-a-resource-connector-in-docker)

## License

MIT — see [LICENSE](LICENSE). Cisco Secure Access software and images are subject to Cisco terms; this repo only wraps Cisco-published install scripts.
