provider "azurerm" {
  features {}

  subscription_id = ""
  client_id       = ""
  client_secret   = ""
  tenant_id       = ""
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-free-test"
  location = "East US"
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-docker-host"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B1s" 
  admin_username      = "adminuser"

  network_interface_ids = [azurerm_network_interface.nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_rsa.pub") 
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-free"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-free"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# NSG RESOURCES

resource "azurerm_network_security_group" "nsg" {
  name                = "nsg-ssh-free"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "0.0.0.0/0" 
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowGrafana"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3000" 
    source_address_prefix      = "0.0.0.0/0"
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "azurerm_network_interface" "nic" {
  name                = "nic-free"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_public_ip" "pip" {
  name                = "pip-free"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard" 
  zones               = ["1"]      

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    environment = "Test"
    cost-center = "Free"
  }
}


resource "null_resource" "docker_setup" {
  depends_on = [
    azurerm_network_interface_security_group_association.nic_nsg_association
  ]

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.pip.ip_address
    user        = "adminuser"
    private_key = file("~/.ssh/id_rsa")
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y docker.io docker-compose git",
      "sudo usermod -aG docker adminuser",
      "mkdir -p ~/app/{loki,grafana} && sync", 
      "sleep 5", 
    ]
  }
}

resource "null_resource" "upload_files" {
  depends_on = [null_resource.docker_setup]

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.pip.ip_address
    user        = "adminuser"
    private_key = file("~/.ssh/id_rsa")
  }
}

resource "null_resource" "start_stack" {
  depends_on = [null_resource.upload_files]

  connection {
    type        = "ssh"
    host        = azurerm_public_ip.pip.ip_address
    user        = "adminuser"
    private_key = file("~/.ssh/id_rsa")
  }
}

output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "grafana_url" {
  value = "http://${azurerm_public_ip.pip.ip_address}:3000"
}