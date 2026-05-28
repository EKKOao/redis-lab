# -*- mode: ruby -*-
# vi: set ft=ruby :

# 6-node Redis Cluster lab: 3 masters + 3 replicas, TLS enabled by default.
# Production notes:
# - Put masters and replicas on separate hosts/racks/AZs.
# - Do not expose Redis ports to the public internet.
# - Use real secret management/PKI instead of the /vagrant shared secret and lab CA paths.

REDIS_NODES = [
  { name: "redis1", ip: "192.168.56.11" },
  { name: "redis2", ip: "192.168.56.12" },
  { name: "redis3", ip: "192.168.56.13" },
  { name: "redis4", ip: "192.168.56.14" },
  { name: "redis5", ip: "192.168.56.15" },
  { name: "redis6", ip: "192.168.56.16" }
]

PROVISION_SCRIPTS = %w[
  01-packages.sh
  02-user.sh
  03-kernel-tuning.sh
  04-storage.sh
  05-swap.sh
  06-backup-nfs-optional.sh
  07-network.sh
  08-install.sh
  09-secrets.sh
  10-tls.sh
  11-config.sh
  12-service.sh
  13-bootstrap-cluster.sh
  14-sudoers.sh
  16-admin-tools.sh
]

Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"

  REDIS_NODES.each do |node|
    config.vm.define node[:name] do |redis|
      redis.vm.hostname = node[:name]
      redis.vm.network "private_network", ip: node[:ip]

      # Dedicated Redis data disk for the LVM-backed /mnt/redis layout.
      # This mirrors a production pattern without relying on the root disk.
      redis.vm.disk :disk, size: "20GB", name: "#{node[:name]}_redis_data"

      redis.vm.provider "virtualbox" do |vb|
        vb.name = node[:name]
        vb.cpus = 2
        vb.memory = 1536
      end

      redis.vm.provision "shell", inline: "set -e; test -f /vagrant/00-env.sh; mkdir -p /vagrant/secrets || true"

      PROVISION_SCRIPTS.each do |script|
        redis.vm.provision "shell", inline: "set -e; test -f /vagrant/#{script}; bash /vagrant/#{script}"
      end
    end
  end
end
