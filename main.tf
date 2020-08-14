terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.23.0"
    }
    random = {
      source = "hashicorp/random"
      version = "~> 2.3.0"
    }
    template = {
      source = "hashicorp/template"
      version = "~> 2.1.2"
    }
  }
  required_version = ">= 0.13"
}

provider "azurerm" {
  features {}
}

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
  value = azurerm_public_ip.app.ip_address
}

resource "azurerm_resource_group" "example" {
  name     = var.resource_group_name # NB this name must be unique within the Azure subscription.
  location = var.location
}

# NB this generates a single random number for the resource group.
resource "random_id" "example" {
  keepers = {
    resource_group = azurerm_resource_group.example.name
  }

  byte_length = 10
}

resource "azurerm_storage_account" "diagnostics" {
  # NB this name must be globally unique as all the azure storage accounts share the same namespace.
  # NB this name must be at most 24 characters long.
  name = "diag${random_id.example.hex}"

  resource_group_name      = azurerm_resource_group.example.name
  location                 = azurerm_resource_group.example.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_virtual_network" "example" {
  name                = "example"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.example.location
  resource_group_name = azurerm_resource_group.example.name
}

resource "azurerm_subnet" "backend" {
  name                 = "backend"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.1.1.0/24"]
}

resource "azurerm_public_ip" "app" {
  name                = "app"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  allocation_method   = "Static"
}

resource "azurerm_network_security_group" "app" {
  name                = "app"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location

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

  security_rule {
    name                       = "ssh"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "app" {
  name                = "app"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location

  ip_configuration {
    name                          = "app"
    primary                       = true
    public_ip_address_id          = azurerm_public_ip.app.id
    subnet_id                     = azurerm_subnet.backend.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.1.1.4" # NB Azure reserves the first four addresses in each subnet address range, so do not use those.
  }
}

resource "azurerm_network_interface_security_group_association" "app" {
  network_interface_id      = azurerm_network_interface.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

data "template_cloudinit_config" "app" {
  part {
    content_type = "text/cloud-config"
    content      = file("cloud-config.yml")
  }

  part {
    content_type = "text/x-shellscript"
    content      = file("provision-app.sh")
  }
}

resource "azurerm_linux_virtual_machine" "app" {
  name                  = "app"
  resource_group_name   = azurerm_resource_group.example.name
  location              = azurerm_resource_group.example.location
  network_interface_ids = [azurerm_network_interface.app.id]
  size                  = "Standard_B1s"
  custom_data           = data.template_cloudinit_config.app.rendered

  admin_username                  = var.admin_username
  admin_password                  = var.admin_password
  disable_password_authentication = false

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.admin_ssh_key_data
  }

  os_disk {
    name    = "app_os"
    caching = "ReadWrite" # TODO is this advisable?

    #disk_size_gb         = 30                # this is optional.
    storage_account_type = "StandardSSD_LRS" # Locally Redundant Storage.
  }

  # see https://docs.microsoft.com/en-us/azure/virtual-machines/linux/cli-ps-findimage
  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.diagnostics.primary_blob_endpoint
  }

  # depends_on = [
  #   azurerm_managed_disk.app_data,
  # ]
}

# # NB this disk will not be initialized by azure.
# #    it will be initialized by cloud-init (see os_profile.custom_data).
# resource "azurerm_managed_disk" "app_data" {
#   name                 = "app_data"
#   resource_group_name  = azurerm_resource_group.example.name
#   location             = azurerm_resource_group.example.location
#   create_option        = "Empty"
#   disk_size_gb         = 10
#   storage_account_type = "StandardSSD_LRS"
# }

# resource "azurerm_virtual_machine_data_disk_attachment" "data" {
#   virtual_machine_id = azurerm_linux_virtual_machine.app.id
#   managed_disk_id    = azurerm_managed_disk.app_data.id
#   lun                = 0
#   caching            = "ReadWrite"       # TODO is this advisable?
# }
