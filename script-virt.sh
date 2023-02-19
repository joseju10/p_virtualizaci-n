#!/bin/bash

# Definimos las variables necesarias
NEW_IMAGE=maquina1.qcow2
NEW_VM_NAME=maquina1
VOL_NAME=voladd
VM_NAME=maquina1

# Creamos la imagen nueva utilizando el comando qemu-img
sudo qemu-img create -f qcow2 -b /var/lib/libvirt/images/bullseye-base.qcow2 /var/lib/libvirt/images/maquina1.qcow2 5G

# Mostramos un mensaje para confirmar que la imagen se ha creado correctamente
echo "Se ha creado la imagen $NEW_IMAGE correctamente."

# Creamos la red interna con NAT
echo "<network>
  <name>intra</name>
  <bridge name='virbr-intra'/>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <ip address='10.10.20.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='10.10.20.100' end='10.10.20.200'/>
    </dhcp>
  </ip>
</network>
" > interna.xml

# Definimos la red interna
virsh -c qemu:///system net-define interna.xml

# Activamos la red interna
virsh -c qemu:///system net-start intra

# La configuramos para que se autoinicie
virsh -c qemu:///system net-autostart intra

# Mostramos las redes existentes
echo "Redes existentes:"
virsh -c qemu:///system net-list --all

# Mostramos la información de la red interna
echo "Información de la red interna:"
virsh -c qemu:///system net-info intra

# Mostramos las direcciones IP asignadas a las máquinas virtuales
echo "Direcciones IP asignadas a las máquinas virtuales:"
virsh -c qemu:///system net-dhcp-leases intra

# Creamos la máquina virtual
sudo virt-install --name maquina1 --memory 1024 --vcpus 1 \
--disk path=/var/lib/libvirt/images/maquina1.qcow2,format=qcow2,bus=virtio --network network=intra \
--os-type linux --os-variant debian10 --noautoconsole \
--boot hd,menu=on

# Mostramos un mensaje para confirmar que la máquina se ha creado correctamente
echo "Se ha creado la máquina virtual $NEW_VM_NAME correctamente."

# Paramos la máquina
virsh -c qemu:///system shutdown maquina1

# Modificamos el archivo /etc/hostname para que tenga el nombre de la máquina
sudo guestfish -d maquina1 -i command 'sudo echo "maquina1" > /etc/hostname'
sudo guestfish -d maquina1 -i command 'sudo ssh-keygen -A'
# Iniciamos la máquina
virsh -c qemu:///system start maquina1

# Mostramos un mensaje para confirmar que se ha modificado el archivo /etc/hostname
echo "Se ha modificado el archivo /etc/hostname de la máquina virtual $NEW_VM_NAME."

# Creamos el volumen utilizando el comando 'virsh vol-create-as'
virsh -c qemu:///system vol-create-as default voladd 1G --format raw

# Mostramos un mensaje para confirmar que el volumen se ha creado correctamente
echo "Se ha creado el volumen $VOL_NAME correctamente."

# Conectamos el volumen a la máquina virtual
virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/voladd vdb --driver=qemu --type disk --subdriver raw --persistent

# Añadimos la ip de la maquina1 a la variable IP
IP= virsh --connect qemu:///system domifaddr maquina1 | awk '/ipv4/ {print $4}' | cut -d'/' -f1

# Creamos un sistema de ficheros XFS en el volumen
ssh debian@$IP 'sudo mkfs.xfs /dev/vdb'

# Montamos el volumen en el directorio /var/www/html
ssh debian@$IP 'sudo mount /dev/vdb /var/www/html'

# Instala en maquina1 el servidor web apache2. 
ssh debian@$IP 'sudo apt update && sudo apt install apache2'

# Copia un fichero index.html a la máquina virtual.
ssh debian@$IP 'echo "Bienvenido a mi sitio web" > /var/www/html/index.html'

# Modificamos los permisos para que el usuario y grupo adecuados tengan acceso
ssh debian@$IP 'sudo chown -R www-data:www-data /var/www/html && sudo chmod -R 755 /var/www/html'

# Muestro la IP:
virsh --connect qemu:///system domifaddr maquina1 | awk '/ipv4/ {print $4}' | cut -d'/' -f1

# Pausar el script y esperar a que el usuario confirme que ha accedido a la página web
read -p "Presione Enter para continuar después de acceder a la página web en la dirección IP $VM_IP."

# Instalo lxc
ssh debian@$IP 'sudo apt-get update && sudo apt-get install -y lxc'

# Creo el contenedor
ssh debian@$IP 'sudo lxc-create -n container1 -t download -- -d ubuntu -r bionic -a amd64'

# Desmontamos el disco
ssh debian@$IP 'sudo umount /var/www/html'

# Lo desasociamos de la máquina
virsh -c qemu:///system detach-disk maquina1 vdb --persistent

# Realizo un snapshot de la maquina
virsh -c qemu:///system snapshot-create-as maquina1 --name instantp --description "Instantánea de la practica" --atomic

# Volvemos a asociarlo y montarlo
virsh -c qemu:///system attach-disk maquina1 /var/lib/libvirt/images/voladd vdb --driver=qemu --type disk --subdriver raw --persistent
ssh debian@$IP 'sudo mount /dev/vdb /var/www/html'