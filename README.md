an example azure ubuntu virtual machine

![](architecture.png)

# Usage (on a Ubuntu Desktop)

Install the tools:

```bash
./provision-tools.sh
```

Login into azure-cli:

```bash
az login
```

List the subscriptions and select the current one if the default is not OK:

```bash
az account list --all
az account set --subscription=<id>
az account show
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
wget -qO- "http://$(terraform output app_ip_address)/test"
```

And open a shell inside the VM:

```bash
ssh "$(terraform output app_ip_address)"
```
