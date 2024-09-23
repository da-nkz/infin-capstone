output "vm_ssh_public_key" {
  value = file("~/.ssh/id_rsa.pub")
  description = "The public SSH key used for the Linux VM"
}

# Output the private IP address of the VM
output "vm_private_ip_address" {
  value = azurerm_network_interface.nic_vm.private_ip_address
  description = "The private IP address of the Linux VM"
}