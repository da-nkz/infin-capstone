
terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = "4.2.0"
    }
  }
}


resource "azurerm_resource_group" "rg" {
  name     = local.resource_group_name
  location = local.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "aks-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "default_sn" {
  name                 = "app-sn"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.10.0/24"]
}

resource "azurerm_subnet" "aks_sn" {
  name                 = "aks-sn"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.20.0/24"]
}

# Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "Apapa"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Standard"
  admin_enabled       = true
}

resource "azurerm_kubernetes_cluster" "aks" {
  name                = "my-aks-cluster"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "dan"
  private_cluster_enabled = "true"

  default_node_pool {
     name       = "default"
    node_count = 1
    vm_size    = "standard_dc2ds_v3"
    auto_scaling_enabled = true
    type = "VirtualMachineScaleSets"
    max_count = 3
    min_count = 1
    vnet_subnet_id = azurerm_subnet.aks_sn.id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    service_cidr      = "10.10.40.0/24"
    dns_service_ip    = "10.10.40.10"  
  }

  kubernetes_version = "1.29.8"
}

# Virtual Machine in the same VNet as AKS
resource "azurerm_subnet" "vmsubnet" {
  name                 = "internal"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.0.0/24"]
}

resource "azurerm_network_interface" "nic_vm" {
  name                = "linuxvm-nic"
  location            = local.location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vmsubnet.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.10.0.49"
  }
}

resource "azurerm_linux_virtual_machine" "linuxvm" {
  name                = "jumpserverforaks"
  resource_group_name = local.resource_group_name
  location            = local.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  admin_password      = "Adminuser123$"
  disable_password_authentication = false
  network_interface_ids = [
    azurerm_network_interface.nic_vm.id,
  ]
  
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }


  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
}

#Bastion deployment
resource "azurerm_subnet" "bastion_subnet" {
  name                 = "AzureBastionSubnet"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.10.2.0/26"]

  depends_on = [ azurerm_resource_group.rg ]
}

resource "azurerm_public_ip" "bastionIP" {
  name                = "bastion_IP"
  location            = local.location
  resource_group_name = local.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  
  depends_on = [ azurerm_resource_group.rg ]
}

resource "azurerm_bastion_host" "bastion" {
  name                = "jumpserverbastion"
  location            = local.location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion_subnet.id
    public_ip_address_id = azurerm_public_ip.bastionIP.id
  }
}

resource "azurerm_public_ip" "appgw_public_ip" {
  name                = "main-appgw-public-ip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_application_gateway" "appgw" {
  name                = "main-appgw"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "appgw-ip-configuration"
    subnet_id = azurerm_subnet.default_sn.id
  }

  frontend_ip_configuration {
    name                 = "appgw-front-end-ip"
    public_ip_address_id = azurerm_public_ip.appgw_public_ip.id
  }

  frontend_port {
    name = "http"
    port = 80
  }

  backend_address_pool {
    name = "appgw-backend-pool"
  }

  backend_http_settings {
    name                  = "appgw-http-settings"
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = "appgw-listener"
    frontend_ip_configuration_name = "appgw-front-end-ip"
    frontend_port_name             = "http"
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = "appgw-rule"
    rule_type                  = "Basic"
    http_listener_name         = "appgw-listener"
    backend_address_pool_name  = "appgw-backend-pool"
    backend_http_settings_name = "appgw-http-settings"
    priority                   = 100  # Added priority
  }
}

/* # Link AKS with ACR (ACR Integration)
resource "azurerm_role_assignment" "aks_acr_role_assignment" {
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}
*/
