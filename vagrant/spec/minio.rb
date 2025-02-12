# MINIO MULTIHOST TESTING CONFIGURATION

# https://developer.hashicorp.com/vagrant/docs/disks/usage
# VAGRANT_EXPERIMENTAL="disks"


# pigsty default singleton vm (3C6G)
Specs = [
  {"name" => "meta",   "ip" => "10.10.10.10", "cpu" => "2",  "mem" => "4096", "image" => "generic/rocky9" },
  {"name" => "node-1", "ip" => "10.10.10.11", "cpu" => "2",  "mem" => "2048", "image" => "generic/rocky9" },
  {"name" => "node-2", "ip" => "10.10.10.12", "cpu" => "2",  "mem" => "2048", "image" => "generic/rocky9" },
]

# Get Preset SSH Key from vagrant/ssh dir (REGENERATE FOR NON-DEVELOPMENT USE)
ssh_prv_key = File.read(File.join(__dir__, 'ssh', 'id_rsa'))
ssh_pub_key = File.readlines(File.join(__dir__, 'ssh', 'id_rsa.pub')).first.strip

Vagrant.configure("2") do |config|
  config.ssh.insert_key = false
  config.vm.box_check_update = false
  config.vm.provision "shell" do |s|
    s.inline = <<-SHELL
        if grep -sq "#{ssh_pub_key}" /home/vagrant/.ssh/authorized_keys; then
          echo "SSH keys already provisioned." ; exit 0;
        fi
        echo "SSH key provisioning."
        sshd=/home/vagrant/.ssh
        mkdir -p ${sshd}; touch ${sshd}/{authorized_keys,config}
        echo #{ssh_pub_key}   >> ${sshd}/authorized_keys
        echo #{ssh_pub_key}   >  ${sshd}/id_rsa.pub      ; chmod 644 ${sshd}/id_rsa.pub
        echo "#{ssh_prv_key}" >  ${sshd}/id_rsa          ; chmod 600 ${sshd}/id_rsa
        if ! grep -q "StrictHostKeyChecking" ${sshd}/config; then
            echo 'StrictHostKeyChecking=no' >> ${sshd}/config
        fi
        chown -R vagrant:vagrant /home/vagrant

        # disk provisioning
        mkfs.xfs /dev/sdb
        mkfs.xfs /dev/sdc
        mkdir /data1 /data2
        mount -t xfs /dev/sdb /data1
        mount -t xfs /dev/sdc /data2

        exit 0
    SHELL
  end

  Specs.each_with_index do |spec, index|
    config.vm.define spec["name"] do |node|
      node.vm.box = spec["image"]
      node.vm.network "private_network", ip: spec["ip"]
      node.vm.hostname = spec["name"]
      node.vm.provider "virtualbox" do |v|
        v.linked_clone = true
        v.customize [
                      "modifyvm", :id, "--cpus", spec["cpu"], "--memory", spec["mem"],
                      "--nictype1", "virtio", "--nictype2", "virtio", "--hwvirtex", "on", "--ioapic", "on",
                      "--rtcuseutc", "on", "--vtxvpid", "on", "--largepages", "on"
                    ]
        v.customize ["guestproperty", "set", :id, "/VirtualBox/GuestAdd/VBoxService/--timesync-set-threshold", 1000]
      end

      node.vm.disk :disk, name: "main", size: "128GB", primary: true
      node.vm.disk :disk, name: "data1", size: "5GB"
      node.vm.disk :disk, name: "data2", size: "5GB"

    end
  end
end


