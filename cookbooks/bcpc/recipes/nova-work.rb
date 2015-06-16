#
# Cookbook Name:: bcpc
# Recipe:: nova-head
#
# Copyright 2013, Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "bcpc::ceph-work"
include_recipe "bcpc::nova-common"

package "nova-compute-#{node['bcpc']['virt_type']}" do
    action :upgrade
end

%w{nova-api nova-network nova-compute nova-novncproxy}.each do |pkg|
    package pkg do
        action :upgrade
    end
    service pkg do
        action [:enable, :start]
        subscribes :restart, "template[/etc/nova/nova.conf]", :delayed
        subscribes :restart, "template[/etc/nova/api-paste.ini]", :delayed
        subscribes :restart, "template[/etc/nova/policy.json]", :delayed
    end
end

service "nova-api" do
    restart_command "service nova-api restart; sleep 5"
end

#  _   _  ____ _  __   __  ____   _  _____ ____ _   _
# | | | |/ ___| | \ \ / / |  _ \ / \|_   _/ ___| | | |
# | | | | |  _| |  \ V /  | |_) / _ \ | || |   | |_| |
# | |_| | |_| | |___| |   |  __/ ___ \| || |___|  _  |
#  \___/ \____|_____|_|   |_| /_/   \_\_| \____|_| |_|
# this patch resolves OpenStack issue #1456321 and BCPC issue #573 -
# fixes DHCP server assignment so that each fixed IP subnet gets its gateway
# address as its DHCP server by default instead of all subnets getting the
# gateway of the lowest subnet
cookbook_file "/tmp/nova-network-dhcp-server.patch" do
    source "nova-network-dhcp-server.patch"
    owner "root"
    mode 00644
end

bash "patch-for-nova-network-dhcp-server" do
    user "root"
    code <<-EOH
       cd /usr/lib/python2.7/dist-packages
       patch -p1 < /tmp/nova-network-dhcp-server.patch
       rv=$?
       if [ $rv -ne 0 ]; then
         echo "Error applying patch ($rv) - aborting!"
         exit $rv
       fi
       cp /tmp/nova-network-dhcp-server.patch .
    EOH
    not_if "test -f /usr/lib/python2.7/dist-packages/nova-network-dhcp-server.patch"
    notifies :restart, "service[nova-api]", :immediately
end

%w{novnc pm-utils memcached sysfsutils}.each do |pkg|
    package pkg do
        action :upgrade
    end
end

template "/etc/nova/ssl-bcpc.pem" do
    source "ssl-bcpc.pem.erb"
    owner "nova"
    group "nova"
    mode 00644
end

template "/etc/nova/ssl-bcpc.key" do
    source "ssl-bcpc.key.erb"
    owner "nova"
    group "nova"
    mode 00600
end

directory "/var/lib/nova/.ssh" do
    owner "nova"
    group "nova"
    mode 00700
end

template "/var/lib/nova/.ssh/authorized_keys" do
    source "nova-authorized_keys.erb"
    owner "nova"
    group "nova"
    mode 00644
end

template "/var/lib/nova/.ssh/known_hosts" do
    source "known_hosts.erb"
    owner "nova"
    group "nova"
    mode 00644
    variables(:servers => search_nodes("recipe", "nova-work"))
end

template "/var/lib/nova/.ssh/id_rsa" do
    source "nova-id_rsa.erb"
    owner "nova"
    group "nova"
    mode 00600
end

template "/var/lib/nova/.ssh/config" do
    source "nova-ssh_config.erb"
    owner "nova"
    group "nova"
    mode 00600
end

template "/etc/default/libvirt-bin" do
  source "libvirt-bin-default.erb"
  owner "root"
  group "root"
  mode 00644
  notifies :restart, "service[libvirt-bin]", :delayed
end

template "/etc/libvirt/libvirtd.conf" do
    source "libvirtd.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[libvirt-bin]", :delayed
end

service "libvirt-bin" do
    action [:enable, :start]
    restart_command "/etc/init.d/libvirt-bin restart"
end

template "/etc/nova/virsh-secret.xml" do
    source "virsh-secret.xml.erb"
    owner "nova"
    group "nova"
    mode 00600
end

bash "set-nova-user-shell" do
    user "root"
    code <<-EOH
        chsh -s /bin/bash nova
    EOH
    not_if "grep nova /etc/passwd | grep /bin/bash"
end

ruby_block 'load-virsh-keys' do
    block do
        %x[ ADMIN_KEY=`ceph --name mon. --keyring /etc/ceph/ceph.mon.keyring auth get-or-create-key client.admin`
            virsh secret-define --file /etc/nova/virsh-secret.xml
            virsh secret-set-value --secret #{get_config('libvirt-secret-uuid')} --base64 "$ADMIN_KEY"
        ]
    end
    not_if { system "virsh secret-list | grep -i #{get_config('libvirt-secret-uuid')} >/dev/null" }
end

bash "remove-default-virsh-net" do
    user "root"
    code <<-EOH
        virsh net-destroy default
        virsh net-undefine default
    EOH
    only_if "virsh net-list | grep -i default"
end

bash "libvirt-device-acls" do
    user "root"
    code <<-EOH
        echo "cgroup_device_acl = [" >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/null\\\", \\\"/dev/full\\\", \\\"/dev/zero\\\"," >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/random\\\", \\\"/dev/urandom\\\"," >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/ptmx\\\", \\\"/dev/kvm\\\", \\\"/dev/kqemu\\\"," >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/rtc\\\", \\\"/dev/hpet\\\", \\\"/dev/net/tun\\\"" >> /etc/libvirt/qemu.conf
        echo "]" >> /etc/libvirt/qemu.conf
    EOH
    not_if "grep -e '^cgroup_device_acl' /etc/libvirt/qemu.conf"
    notifies :restart, "service[libvirt-bin]", :delayed
end

if node['bcpc']['virt_type'] == "kvm" then
    %w{amd intel}.each do |arch|
        bash "enable-kvm-#{arch}" do
            user "root"
            code <<-EOH
                modprobe kvm_#{arch}
                echo 'kvm_#{arch}' >> /etc/modules
            EOH
            not_if "grep -e '^kvm_#{arch}' /etc/modules"
        end
    end
end

cron "restart-nova-kludge" do
  action :delete
end

file "/usr/local/bin/nova-service-restart" do
  action :delete
end

file "/usr/local/bin/nova-service-restart-wrapper" do
  action :delete
end

cookbook_file "/tmp/nova_api_metadata_base.patch" do
    source "nova_api_metadata_base.patch"
    owner "root"
    mode 0644
end 

bash "patch-for-ip-hostnames-metadata" do
    user "root"
    code <<-EOH
        cd /usr/lib/python2.7/dist-packages/
        cp nova/api/metadata/base.py nova/api/metadata/base.py.prepatch
        patch -p1 < /tmp/nova_api_metadata_base.patch
        rv=$?
        if [ $rv -ne 0 ]; then
          echo "Error applying patch ($rv) - aborting!"
          exit $rv
        fi
        cp /tmp/nova_api_metadata_base.patch .
    EOH
    not_if "grep -q 'THIS FILE PATCHED BY BCPC' /usr/lib/python2.7/dist-packages/nova/api/metadata/base.py"
    notifies :restart, "service[nova-api]", :immediately
end 

cookbook_file "/tmp/nova_network_linux_net.patch" do
    source "nova_network_linux_net.patch"
    owner "root"
    mode 0644
end 

bash "patch-for-ip-hostnames-networking" do
    user "root"
    code <<-EOH
        cd /usr/lib/python2.7/dist-packages/
        cp nova/network/linux_net.py nova/network/linux_net.py.prepatch
        patch -p1 < /tmp/nova_network_linux_net.patch
        rv=$?
        if [ $rv -ne 0 ]; then
          echo "Error applying patch ($rv) - aborting!"
          exit $rv
        fi
        cp /tmp/nova_network_linux_net.patch .
    EOH
    not_if "grep -q 'THIS FILE PATCHED BY BCPC' /usr/lib/python2.7/dist-packages/nova/network/linux_net.py"
    notifies :restart, "service[nova-compute]", :immediately
    notifies :restart, "service[nova-network]", :immediately
end 

include_recipe "bcpc::cobalt"
