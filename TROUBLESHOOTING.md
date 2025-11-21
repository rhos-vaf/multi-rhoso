# Troubleshooting Guide

This guide covers common issues you may encounter when deploying multi-RHOSO instances.

## Galera Authentication Failures

**Symptom:** Galera pods (rhoso1-galera-0, rhoso1-cell1-galera-0) in CrashLoopBackOff with logs showing:
```
ERROR 1698 (28000): Access denied for user 'root'@'localhost'
WARNING: password retrieved from cluster failed authentication
```

**Cause:** The `osp-secret` wasn't created before deploying control plane services.

**Fix:** This is now automatically handled by the wrapper. If you encounter this:
```bash
# Redeploy control plane (creates secrets automatically)
source config/rhoso1.env && make controlplane
```

**Prevention:** Always use `make instance` or `make controlplane` which now includes automatic secret creation.

## DNS Pods CrashLoopBackOff

**Symptom:** dnsmasq pods stuck in Init:CrashLoopBackOff with logs showing:
```
dnsmasq: missing parameter at line 1 of /etc/dnsmasq.d/config.cfg
```

**Cause:** DNS configuration is missing the upstream DNS server parameter.

**Fix:** This is now automatically handled by the wrapper. If you encounter this:
```bash
# Redeploy control plane with proper DNS configuration
source config/rhoso1.env && make controlplane
```

**Prevention:** The wrapper now passes `CTLPLANE_IPV4_DNS_SERVER` automatically to configure DNS properly.

## Hypervisors Not Appearing

**Symptom:** `openstack hypervisor list` returns empty even though `openstack compute service list` shows nova-compute as "up"

**Cause:** Nova host discovery hasn't run to map compute hosts to cells.

**Fix:** This is now automatically handled after dataplane deployment. If you need to run manually:
```bash
# Get the nova-cell0-conductor pod name
oc -n rhoso1 exec -it $(oc get pod -n rhoso1 -l app=nova-cell0-conductor --no-headers -o custom-columns=":metadata.name" | head -1) -- nova-manage cell_v2 discover_hosts --verbose
```

**Verification:**
```bash
oc -n rhoso1 rsh openstackclient openstack hypervisor list
```

**Prevention:** The `make dataplane` target now automatically runs host discovery after deployment.

## Control Plane Not Ready Before Dataplane

**Symptom:** Dataplane deployment fails or EDPM compute can't connect because control plane services aren't fully ready

**Cause:** Deploying dataplane before control plane is fully operational

**Fix:** This is now automatically handled by the `wait-controlplane` target. If deploying manually:
```bash
source config/rhoso1.env && make controlplane
source config/rhoso1.env && make wait-controlplane
source config/rhoso1.env && make dataplane
```

**Monitor control plane status:**
```bash
oc -n rhoso1 get openstackcontrolplane -w
```

Wait for STATUS column to show "True" and MESSAGE to show "Setup complete".

**Prevention:** The `make instance` target now includes `wait-controlplane` automatically.

## NNCP Not Applied

**Symptom:** VLAN interfaces not created on CRC node

**Check:**
```bash
oc get nncp
oc describe nncp enp6s0-crc
```

**Fix:**
```bash
source config/rhoso1.env && make nncp  # For first instance
```

## MetalLB Not Assigning IPs

**Symptom:** Services stuck in `<pending>` for EXTERNAL-IP

**Check:**
```bash
oc get ipaddresspool -n metallb-system
oc get svc -n rhoso1 -o wide | grep LoadBalancer
```

**Common causes:**
1. Secondary IPs not configured on CRC node
2. Pool name mismatch in service annotations
3. Namespace not in pool's `serviceAllocation.namespaces`

**Fix:**
```bash
# Verify secondary IPs exist
make verify-nncp

# Recreate MetalLB config
source config/rhoso2.env && make metallb-config
```

## EDPM Compute Not Connecting

**Symptom:** Nova compute service shows `down` state

**Check:**
```bash
# On EDPM node
sudo systemctl status nova-compute
sudo journalctl -u nova-compute -n 50

# Check RabbitMQ connectivity
curl -k https://172.27.0.80:5671
```

**Common causes:**
1. VLAN interfaces not configured on EDPM node
2. Firewall blocking traffic
3. RabbitMQ LoadBalancer IP not reachable
4. Incorrect hostname on EDPM node

**Fix:**
```bash
# Verify EDPM node can reach control plane
ping 172.27.0.80  # From EDPM node

# Check hostname matches config
ssh -i install_yamls/out/edpm/ansibleee-ssh-key-id_rsa root@192.168.122.101 hostname
# Should return: edpm-compute-1.example.com

# Check ansible logs
oc logs -n rhoso2 -l app=openstackansibleee
```

## Non-Prefixed MetalLB Pools Conflict

**Symptom:** Error when running `make metallb-config`:
```
Error from server (Forbidden): CIDR "192.168.122.80/29" in pool "rhoso1-ctlplane" overlaps with already defined CIDR
```

**Cause:** Non-prefixed MetalLB pools exist from vanilla `install_yamls` deployment with `NETWORK_ISOLATION=true`.

**Check:**
```bash
oc get ipaddresspool -n metallb-system
```

**Fix:** The `make metallb-config` target intelligently detects the deployment state:
- **First RHOSO deployment**: Automatically removes non-prefixed pools (one-time cleanup) and creates namespace-prefixed pools
- **Additional deployments**: Skips cleanup and only creates/patches namespace-prefixed pools

Simply run the normal deployment:
```bash
source config/rhoso1.env && make instance
# or
source config/rhoso1.env && make metallb-config
```

**Manual cleanup (if needed):**
```bash
# Delete non-prefixed pools manually
oc delete ipaddresspool ctlplane internalapi storage tenant designateext storagemgmt -n metallb-system --ignore-not-found=true
oc delete l2advertisement ctlplane internalapi storage tenant designateext storagemgmt -n metallb-system --ignore-not-found=true
```

## Duplicate IPs or Network Conflicts

**Symptom:** Services unreachable, IP conflicts in logs

**Prevention:**
- Always use unique subnet prefixes per instance
- Never run `make nncp` twice for different instances
- Verify configuration files before deployment

**Recovery:**
```bash
# Check current NNCP configuration
oc get nncp enp6s0-crc -o yaml

# Manually patch if needed (see NNCP_OVERWRITE_FIX.md in install_yamls)
```
