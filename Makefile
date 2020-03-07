all: architecture.png terraform-apply

terraform-init:
	CHECKPOINT_DISABLE=1 \
	TF_LOG=TRACE \
	TF_LOG_PATH=terraform.log \
	terraform init
	CHECKPOINT_DISABLE=1 \
	terraform -v

terraform-apply:
	CHECKPOINT_DISABLE=1 \
	TF_LOG=TRACE \
	TF_LOG_PATH=terraform.log \
	TF_VAR_admin_ssh_key_data="$(shell cat ~/.ssh/id_rsa.pub)" \
	time terraform apply

terraform-destroy:
	CHECKPOINT_DISABLE=1 \
	TF_LOG=TRACE \
	TF_LOG_PATH=terraform.log \
	TF_VAR_admin_ssh_key_data="$(shell cat ~/.ssh/id_rsa.pub)" \
	time terraform destroy

terraform-destroy-app:
	CHECKPOINT_DISABLE=1 \
	TF_LOG=TRACE \
	TF_LOG_PATH=terraform.log \
	TF_VAR_admin_ssh_key_data="$(shell cat ~/.ssh/id_rsa.pub)" \
	time terraform destroy -target azurerm_linux_virtual_machine.app

architecture.png: architecture.uxf
	java -jar ~/Applications/Umlet/umlet.jar \
		-action=convert \
		-format=png \
		-filename=$< \
		-output=$@.tmp
	pngquant --ext .png --force $@.tmp.png
	mv $@.tmp.png $@

.PHONY: terraform-init terraform-apply
