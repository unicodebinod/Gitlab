# variables
locals {
  Ressource_Group_Name     = "gitlab-rg"
  Ressource_Group_Location = "West Europe"
}

#create resource group
resource "azurerm_resource_group" "gitlab-rg" {
  name     = local.Ressource_Group_Name
  location = local.Ressource_Group_Location
}
/*
#create container registry
resource "azurerm_container_registry" "gitlab82178acr" {
  name                = "containerRegistry82178"
  resource_group_name = local.Ressource_Group_Name
  location            = local.Ressource_Group_Location
  sku                 = "Standard"
  admin_enabled       = true

  depends_on = [azurerm_resource_group.gitlab-rg]
}
*/

#create  Public-IP for gitlab-vm1
resource "azurerm_public_ip" "gitlab_public_ip" {
  name                = "my-gitlab-ip"
  resource_group_name = local.Ressource_Group_Name
  location            = local.Ressource_Group_Location
  allocation_method   = "Static"
  depends_on          = [azurerm_resource_group.gitlab-rg]
}

#create virtual Network
resource "azurerm_virtual_network" "gitlab_vnet" {
  name                = "my-gitlab-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = local.Ressource_Group_Location
  resource_group_name = local.Ressource_Group_Name
  depends_on          = [azurerm_resource_group.gitlab-rg]
}

#subnet(internal network)
resource "azurerm_subnet" "gitlab_subnet" {
  name                 = "my-gitlab-subnet"
  resource_group_name  = local.Ressource_Group_Name
  virtual_network_name = "my-gitlab-vnet"
  address_prefixes     = ["10.0.2.0/24"]
  depends_on           = [azurerm_virtual_network.gitlab_vnet]
}

resource "azurerm_network_interface" "gitlab_nic" {
  name                = "my-gitlab-nic"
  location            = local.Ressource_Group_Location
  resource_group_name = local.Ressource_Group_Name

  ip_configuration {
    name = "internal"
    //subnet.id=label of subnet
    subnet_id                     = azurerm_subnet.gitlab_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.gitlab_public_ip.id

  }

  depends_on = [azurerm_subnet.subnet, azurerm_public_ip.gitlab_public_ip]
}


# gitlab-VM erstellen
resource "azurerm_linux_virtual_machine" "gitlab_vm" {
  name                = "my-gitlab-vm"
  size                = "Standard_B1s"
  admin_username      = "azureuser"
  location            = local.Ressource_Group_Location
  resource_group_name = local.Ressource_Group_Name
  network_interface_ids = [azurerm_network_interface.gitlab_nic.id,
  ]

  depends_on = [azurerm_network_interface.networkInterface]

  admin_ssh_key {
    username = "azureuser"
    // public_key = file("~/.ssh/id_rsa.pub")
    //line 61 is used before sshkey way gererated. 
    //After key is generated ,immediately the path has to be changed as line 63
    public_key = file("./sshkey.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}

# NSG für gitlab-vm erstellen
resource "azurerm_network_security_group" "gitlab_nsg" {
  name                = "my-gitlab-nsg"
  location            = local.Ressource_Group_Location
  resource_group_name = local.Ressource_Group_Name
  depends_on          = [azurerm_resource_group.gitlab-rg]
}
#firewall rules for sshd
resource "azurerm_network_security_rule" "sshd" {
  name                        = "sshd"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.Ressource_Group_Name
  network_security_group_name = azurerm_network_security_group.gitlab_nsg.name

  depends_on = [azurerm_network_security_group.gitlab_nsg]
}

#firewall rules for web
resource "azurerm_network_security_rule" "web" {
  name                        = "allow_http"
  priority                    = 101
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.Ressource_Group_Name
  network_security_group_name = azurerm_network_security_group.gitlab_nsg.name

  depends_on = [azurerm_network_security_group.gitlab_nsg]
}

#allow outgoing network traffic 
resource "azurerm_network_security_rule" "outgoing" {
  name                        = "all_out"
  priority                    = 201
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.Ressource_Group_Name
  network_security_group_name = azurerm_network_security_group.gitlan_nsg.name


  depends_on = [azurerm_network_security_group.gitlab_nsg]
}

# Verbinden NSG mit gitlab-vm-NIC1 
resource "azurerm_network_interface_security_group_association" "gitlab_vm1_association" {
  network_interface_id      = azurerm_network_interface.gitlab_nic.id
  network_security_group_id = azurerm_network_security_group.gitlab_nsg.id

  depends_on = [azurerm_network_interface.gitlab_nic, azurerm_network_security_group.gitlan_nsg]

}