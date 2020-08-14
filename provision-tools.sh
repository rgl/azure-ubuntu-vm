#!/bin/bash
set -euxo pipefail

# install dependencies.
sudo apt-get install -y apt-transport-https make unzip jq

# install terraform.
# see https://www.terraform.io/downloads.html
artifact_url=https://releases.hashicorp.com/terraform/0.13.0/terraform_0.13.0_linux_amd64.zip
artifact_sha=9ed437560faf084c18716e289ea712c784a514bdd7f2796549c735d439dbe378
artifact_path="/tmp/$(basename $artifact_url)"
wget -qO $artifact_path $artifact_url
if [ "$(sha256sum $artifact_path | awk '{print $1}')" != "$artifact_sha" ]; then
    echo "downloaded $artifact_url failed the checksum verification"
    exit 1
fi
sudo unzip -o $artifact_path -d /usr/local/bin
rm $artifact_path
CHECKPOINT_DISABLE=1 terraform version

# install azure-cli.
# see https://docs.microsoft.com/en-us/cli/azure/install-azure-cli-apt?view=azure-cli-latest
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" \
    | sudo tee /etc/apt/sources.list.d/azure-cli.list
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
sudo apt-get update
sudo apt-get install -y azure-cli='2.10.1-*'
az version
