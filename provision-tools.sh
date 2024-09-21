#!/bin/bash
set -euxo pipefail

# install dependencies.
sudo apt-get install -y apt-transport-https make unzip jq

# install terraform.
# see https://www.terraform.io/downloads.html
artifact_url=https://releases.hashicorp.com/terraform/1.9.6/terraform_1.9.6_linux_amd64.zip
artifact_path="/tmp/$(basename $artifact_url)"
wget -qO $artifact_path $artifact_url
sudo unzip -o $artifact_path -d /usr/local/bin
rm $artifact_path
CHECKPOINT_DISABLE=1 terraform version

# install azure-cli.
# see https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt?view=azure-cli-latest
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/azure-cli.list
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y azure-cli='2.64.0-*'
az version
