# NB you can test the relative speed from you browser to a location using https://azurespeedtest.azurewebsites.net/
# get the available locations with: az account list-locations --output table
variable "location" {
  default = "France Central" # see https://azure.microsoft.com/en-us/global-infrastructure/france/
}

# NB this name must be unique within the Azure subscription.
#    all the other names must be unique within this resource group.
variable "resource_group_name" {
  default = "rgl-ubuntu-vm-example"
}

variable "admin_username" {
  default = "rgl"
}

variable "admin_password" {
  default = "HeyH0Password"
}

# NB when you run make terraform-apply this is set from the TF_VAR_admin_ssh_key_data environment variable, which comes from the ~/.ssh/id_rsa.pub file.
variable "admin_ssh_key_data" {}

output "app_ip_address" {
  value = "${azurerm_public_ip.app.ip_address}"
}

provider "azurerm" {}

resource "azurerm_resource_group" "example" {
  name     = "${var.resource_group_name}" # NB this name must be unique within the Azure subscription.
  location = "${var.location}"
}

# NB this generates a single random number for the resource group.
resource "random_id" "example" {
  keepers = {
    resource_group = "${azurerm_resource_group.example.name}"
  }

  byte_length = 10
}

resource "azurerm_storage_account" "diagnostics" {
  # NB this name must be globally unique as all the azure storage accounts share the same namespace.
  # NB this name must be at most 24 characters long.
  name = "diag${random_id.example.hex}"

  resource_group_name      = "${azurerm_resource_group.example.name}"
  location                 = "${azurerm_resource_group.example.location}"
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_virtual_network" "example" {
  name                = "example"
  address_space       = ["10.1.0.0/16"]
  location            = "${azurerm_resource_group.example.location}"
  resource_group_name = "${azurerm_resource_group.example.name}"
}

resource "azurerm_subnet" "backend" {
  name                 = "backend"
  resource_group_name  = "${azurerm_resource_group.example.name}"
  virtual_network_name = "${azurerm_virtual_network.example.name}"
  address_prefix       = "10.1.1.0/24"
}

resource "azurerm_public_ip" "app" {
  name                         = "app"
  resource_group_name          = "${azurerm_resource_group.example.name}"
  location                     = "${azurerm_resource_group.example.location}"
  public_ip_address_allocation = "Static"
}

resource "azurerm_network_security_group" "app" {
  name                = "app"
  resource_group_name = "${azurerm_resource_group.example.name}"
  location            = "${azurerm_resource_group.example.location}"

  # NB By default, a security group, will have the following Inbound rules:
  #     | Priority | Name                           | Port  | Protocol  | Source            | Destination     | Action  |
  #     |----------|--------------------------------|-------|-----------|-------------------|-----------------|---------|
  #     | 65000    | AllowVnetInBound               | Any   | Any       | VirtualNetwork    | VirtualNetwork  | Allow   |
  #     | 65001    | AllowAzureLoadBalancerInBound  | Any   | Any       | AzureLoadBalancer | Any             | Allow   |
  #     | 65500    | DenyAllInBound                 | Any   | Any       | Any               | Any             | Deny    |
  # NB By default, a security group, will have the following Outbound rules:
  #     | Priority | Name                           | Port  | Protocol  | Source            | Destination     | Action  |
  #     |----------|--------------------------------|-------|-----------|-------------------|-----------------|---------|
  #     | 65000    | AllowVnetOutBound              | Any   | Any       | VirtualNetwork    | VirtualNetwork  | Allow   |
  #     | 65001    | AllowInternetOutBound          | Any   | Any       | Any               | Internet        | Allow   |
  #     | 65500    | DenyAllOutBound                | Any   | Any       | Any               | Any             | Deny    |

  security_rule {
    name                       = "app"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "app" {
  name                      = "app"
  resource_group_name       = "${azurerm_resource_group.example.name}"
  location                  = "${azurerm_resource_group.example.location}"
  network_security_group_id = "${azurerm_network_security_group.app.id}"

  ip_configuration {
    name                          = "app"
    primary                       = true
    public_ip_address_id          = "${azurerm_public_ip.app.id}"
    subnet_id                     = "${azurerm_subnet.backend.id}"
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.1.4"                     # NB Azure reserves the first four addresses in each subnet address range, so do not use those.
  }
}

data "template_cloudinit_config" "app" {
  part {
    content_type = "text/cloud-config"
    content      = "${file("cloud-config.yml")}"
  }

  part {
    content_type = "text/x-shellscript"
    content      = "${file("provision-app.sh")}"
  }
}

resource "azurerm_virtual_machine" "app" {
  name                  = "app"
  resource_group_name   = "${azurerm_resource_group.example.name}"
  location              = "${azurerm_resource_group.example.location}"
  network_interface_ids = ["${azurerm_network_interface.app.id}"]
  vm_size               = "Standard_B1s"

  delete_os_disk_on_termination    = true
  delete_data_disks_on_termination = true

  storage_os_disk {
    name          = "app_os"
    caching       = "ReadWrite" # TODO is this advisable?
    create_option = "FromImage"

    #disk_size_gb      = "30"              # this is optional.
    managed_disk_type = "StandardSSD_LRS" # Locally Redundant Storage.
  }

  # see https://docs.microsoft.com/en-us/azure/virtual-machines/linux/cli-ps-findimage
  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  # NB this disk will not be initialized by azure.
  #    it will be initialized by cloud-init (see os_profile.custom_data).
  storage_data_disk {
    name              = "ubuntu_data"
    caching           = "ReadWrite"       # TODO is this advisable?
    create_option     = "Empty"
    disk_size_gb      = "10"
    lun               = 0
    managed_disk_type = "StandardSSD_LRS"
  }

  os_profile {
    computer_name  = "app"
    admin_username = "${var.admin_username}"
    admin_password = "${var.admin_password}"
    custom_data    = "${data.template_cloudinit_config.app.rendered}"
  }

  os_profile_linux_config {
    disable_password_authentication = false

    ssh_keys {
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
      key_data = "${var.admin_ssh_key_data}"
    }
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = "${azurerm_storage_account.diagnostics.primary_blob_endpoint}"
  }
}
