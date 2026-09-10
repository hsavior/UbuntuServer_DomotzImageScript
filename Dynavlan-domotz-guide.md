# DynaVLAN on a Domotz Collector

Optional add-on for a collector plugged into a trunk port.

A collector on a trunk port sees only the untagged network, so devices on the
tagged VLANs are never discovered. [DynaVLAN](https://github.com/pereljon/dynavlan)
detects the VLANs present on the port, brings each one up with DHCP, and
restarts the Collector so it discovers devices on all of them.

DynaVLAN is third-party open-source software, not maintained by Domotz.

---

## When you need it

Install it if the collector is on a **trunk port** carrying tagged VLANs.

Skip it if the collector is on a normal access port. On a flat network it has
nothing to do, and it adds several minutes to every boot while it looks.

---

## Installing

On the collector:

```
wget -O- https://raw.githubusercontent.com/hsavior/UbuntuServer_DomotzImageScript/refs/heads/main/setup-dynavlan-domotz.sh | bash
```

The script checks the prerequisites, installs DynaVLAN, and sets
`RESTART_SNAPS=domotzpro-agent-publicstore` so the Collector restarts whenever
the VLANs change.

Nothing is applied while the script runs. DynaVLAN takes effect at the next
boot, or immediately with `sudo dynavlan --boot`.

### Prerequisites

- netplan 0.106 or newer, with the `systemd-networkd` renderer
- Root access
- `tcpdump` and `lldpd`, which the script installs

### Requirement: named interfaces in netplan

This is the one thing that will stop it working.

In netplan, a VLAN's `link:` must reference a **definition ID**, not a kernel
interface name. A configuration that defines interfaces with a wildcard:

```yaml
all-eth:
    match:
        name: "eth*"
    dhcp4: true
```

has only one definition ID, `all-eth`. There is no definition called `eth0`, so
DynaVLAN's generated config is rejected:

```
netplan generate rejected dynavlan's own config:
eth0.666: interface 'eth0' is not defined
```

DynaVLAN rolls its config back and the service fails. The fix is to name each
interface:

```yaml
network:
    version: 2
    ethernets:
        eth0:
            dhcp4: true
            dhcp6: false
            accept-ra: false
            optional: true
        eth1:
            dhcp4: true
            dhcp6: false
            accept-ra: false
            optional: true
```

`setup-nanopi-domotz.sh` writes it this way as of version 1.1.0. Collectors
provisioned with an earlier version need `/etc/netplan/00-installer-config.yaml`
rewritten before DynaVLAN will work.

---

## Checking it worked

```
systemctl status dynavlan --no-pager -l
sudo journalctl -u dynavlan --no-pager -n 40
ip -br a
```

A healthy run looks like this:

```
dynavlan[info]: trunk eth0: 2 tags detected [55 666]
dynavlan[notice]: restarted snap domotzpro-agent-publicstore
```

and `ip -br a` shows the VLAN interfaces with addresses:

```
eth0.55    UP    192.168.55.122/24
eth0.666   UP    192.168.66.122/24
```

A VLAN with no DHCP server comes up without an address. That is not a DynaVLAN
failure, it just has nothing to lease.

Finally, confirm in the Domotz portal that devices from each VLAN's subnet are
being discovered. That is the actual goal.

---

## Static addresses on the VLANs

DynaVLAN is DHCP-only by design. There is no static addressing option. Three
ways to get stable addresses, easiest first.

### 1. DHCP reservations

Add a reservation on each VLAN's DHCP server. DynaVLAN keeps managing
everything and the addresses stop moving.

The VLAN interfaces share the parent interface's MAC address, but each VLAN is
a separate DHCP scope, so one reservation per scope is fine.

If a reservation does not take, the cause is usually that systemd-networkd
sends a DUID-based client identifier rather than the bare MAC, so the server
never matches it. Fixing that needs `dhcp-identifier: mac` on the interface,
and DynaVLAN owns its generated file, which makes this route's weak point.

### 2. Exclude specific VLANs and define them yourself

Use the ignore list in `/etc/dynavlan.conf` for the VLANs you want to manage,
and let DynaVLAN handle the rest:

```
sudo grep -n -i ignore /etc/dynavlan.conf
sudo nano /etc/dynavlan.conf
```

Then define the excluded VLANs in a netplan file of your own. DynaVLAN owns
exactly one generated file and leaves every other netplan file alone, so the
two coexist.

### 3. Write the VLANs by hand

If the VLAN IDs are known and fixed at a site, this is the most predictable
option. Create `/etc/netplan/10-static-vlans.yaml`:

```yaml
network:
    version: 2
    vlans:
        eth0.55:
            id: 55
            link: eth0
            dhcp4: false
            addresses: [192.168.55.10/24]
        eth0.666:
            id: 666
            link: eth0
            dhcp4: false
            addresses: [192.168.66.10/24]
```

Then:

```
sudo chmod 600 /etc/netplan/10-static-vlans.yaml
sudo netplan generate && sudo netplan apply
```

Note there is no gateway, no routes and no nameservers on those VLANs. That is
deliberate. The collector's default route belongs on the uplink interface;
giving monitoring VLANs their own default routes is how traffic ends up leaving
the wrong interface. DynaVLAN makes the same choice, which is why routed mode
is opt-in behind `VLAN_ROUTES`.

---

## Useful settings in /etc/dynavlan.conf

Every key is documented next to its default in the file itself. The ones that
matter most here:

| Key | What it does |
|---|---|
| `RESTART_SNAPS` | Snaps to restart after VLAN changes. The setup script sets this to `domotzpro-agent-publicstore`. |
| `RESTART_SERVICES` | Systemd units to restart after VLAN changes |
| `RESTART_ON_NEW_SUBNET` | Restart targets when a new IPv4 subnet appears. Default `true`. |
| `VLAN_ROUTES` | Opt-in routed mode, accepting DHCP default routes per VLAN |
| `VLAN_ROUTE_METRIC_START` | Starting metric for per-VLAN routes, kept above the uplink |
| `REMOVE_ON_CARRIER_LOSS` | Prune VLANs from a trunk that loses link. Default `true`. |
| `SNIFF_SECONDS` | How long to sniff for tagged traffic per interface |
| `RESCAN_MINUTES` | Rescan timer interval. Default every 5 minutes. |
| `LOG_LEVEL` | Set to `debug` for detailed detection output |

Edit with `sudo nano /etc/dynavlan.conf`. The setup script saves the original
as `/etc/dynavlan.conf.bak`.

---

## Boot time

DynaVLAN waits for carrier on every interface before deciding whether to sniff
it, and does two passes at boot. On a board with unused ports that adds up:

```
dynavlan[info]: no carrier on eth1 within 30s; skipping detection on it
dynavlan[info]: no carrier on eth2 within 30s; skipping detection on it
```

On a three-port R5S with one cable connected, that is roughly three and a half
minutes from boot to the VLANs being up. Use the ignore list for ports that
stay empty in production to cut most of it.

---

## Troubleshooting

**`dynavlan.service` failed, log says `interface 'eth0' is not defined`.**
The netplan configuration uses wildcard matching. See "Requirement: named
interfaces in netplan" above.

**Service failed with no useful output.**
Check the unit name. It is `dynavlan.service`, not `dynavlan-boot`:

```
sudo journalctl -u dynavlan --no-pager -n 80
```

**VLANs are detected but no addresses appear.**
Those VLANs likely have no DHCP server. Confirm with `sudo journalctl -u
dynavlan`, then use a static configuration as above.

**Interfaces stay in PROMISC mode.**
Expected while detection runs; DynaVLAN puts interfaces into promiscuous mode
so `tcpdump` can see tagged frames.

**Nothing is detected on a port you believe is a trunk.**
Confirm the switch port is tagging VLANs toward the collector, and that traffic
is actually flowing on them. Detection is passive, so a silent VLAN is
invisible. Raise `SNIFF_SECONDS` and set `LOG_LEVEL=debug`, then
`sudo dynavlan --rescan`.

---

## Reference

- DynaVLAN project: https://github.com/pereljon/dynavlan
- Collector setup guide: [Nanopi-domotz-setup-guide.md](Nanopi-domotz-setup-guide.md)
