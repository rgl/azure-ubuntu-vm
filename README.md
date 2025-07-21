an example azure ubuntu virtual machine

![](architecture.png)

# Usage (on a Ubuntu Desktop)

Install the tools:

```bash
./provision-tools.sh
```

Login into azure:

```bash
az login
```

List the subscriptions:

```bash
az account list --all
az account show
```

Set the subscription:

```bash
export ARM_SUBSCRIPTION_ID="<YOUR-SUBSCRIPTION-ID>"
az account set --subscription "$ARM_SUBSCRIPTION_ID"
```

Review `main.tf` and maybe change the `location` variable.

Initialize terraform:

```bash
make terraform-init
```

Launch the example:

```bash
make terraform-apply
```

At VM initialization time [cloud-init](https://cloudinit.readthedocs.io/en/latest/index.html) will run the `provision-app.sh` script to launch the example application.

After VM initialization is done (check the boot diagnostics serial log for cloud-init entries), test the `app` endpoint:

```bash
while ! wget -qO- "http://$(terraform output --raw app_ip_address)/test"; do sleep 3; done
while ! wget -qO- "http://[$(terraform output --raw app_ipv6_ip_address)]/test"; do sleep 3; done
```

Open a shell inside the VM, and poke it:

```bash
ssh "$(terraform output --raw app_ip_address)"
sudo cat /etc/netplan/50-cloud-init.yaml
ip addr
ip -4 route
ip -6 route
ping -6 -n -c 3 2606:4700:4700::1111    # cloudflare dns.
ping -6 -n -c 3 2606:4700:4700::1001    # cloudflare dns.
ping -6 -n -c 3 ff02::1                 # all nodes.   # NB does not work in azure.
ping -6 -n -c 3 ff02::2                 # all routers. # NB does not work in azure.
ping -4 -n -c 3 ip6.me
ping -6 -n -c 3 ip6.me
dig -4 aaaa ip6.me
dig -6 aaaa ip6.me @2606:4700:4700::1111
curl -4 https://ip6.me/api/ # get the vm public ipv4 address.
curl -6 https://ip6.me/api/ # get the vm public ipv6 address.
curl http://ip6only.me/api/ # get the vm public ipv6 address.
curl http://10.1.1.4/test   # try the app private ipv4 endpoint.
curl http://[fd00::4]/test  # try the app private ipv6 endpoint.
ipv6_public_test_url="http://[$(curl -6 -s https://ip6.me/api/ | awk -F, '{print $2}')]/test"
curl "$ipv6_public_test_url" # try the app public ipv6 endpoint.
echo "go to https://dnschecker.org/server-headers-check.php and test the app ipv6 url:
$ipv6_public_test_url"
exit
```

Destroy the example:

```bash
make terraform-destroy
```
