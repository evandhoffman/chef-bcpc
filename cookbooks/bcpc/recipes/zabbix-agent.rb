#
# Cookbook Name:: bcpc
# Recipe:: zabbix-agent
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

if node['bcpc']['enabled']['monitoring'] then

    include_recipe "bcpc::default"

    cookbook_file "/tmp/zabbix-agent.tar.gz" do
        source "bins/zabbix-agent.tar.gz"
        owner "root"
        mode 00444
    end

    bash "install-zabbix-agent" do
        code <<-EOH
            tar zxf /tmp/zabbix-agent.tar.gz -C /usr/local/
        EOH
        not_if "test -f /usr/local/sbin/zabbix_agentd"
    end

    user node['bcpc']['zabbix']['user'] do
        shell "/bin/false"
        home "/var/log"
        gid node['bcpc']['zabbix']['group']
        system true
    end

    directory "/var/log/zabbix" do
        user node['bcpc']['zabbix']['user']
        group node['bcpc']['zabbix']['group']
        mode 00755
    end

    template "/etc/init/zabbix-agent.conf" do
        source "upstart-zabbix-agent.conf.erb"
        owner "root"
        group "root"
        mode 00644
        notifies :restart, "service[zabbix-agent]", :delayed
    end

    template "/usr/local/etc/zabbix_agent.conf" do
        source "zabbix_agent.conf.erb"
        owner node['bcpc']['zabbix']['user']
        group "root"
        mode 00600
        notifies :restart, "service[zabbix-agent]", :delayed
    end

    template "/usr/local/etc/zabbix_agentd.conf" do
        source "zabbix_agentd.conf.erb"
        owner node['bcpc']['zabbix']['user']
        group "root"
        mode 00600
        variables(:mysql_servers => search_nodes("recipe", "mysql-common"))
        notifies :restart, "service[zabbix-agent]", :delayed
    end

    service "zabbix-agent" do
        provider Chef::Provider::Service::Upstart
        action [:enable, :start]
    end

    template "/usr/local/etc/zabbix_agentd.conf.d/zabbix-openstack.conf" do
        source "zabbix_openstack.conf.erb"
        owner node['bcpc']['zabbix']['user']
        group "root"
        mode 00600
        only_if do get_cached_head_node_names.include?(node['hostname']) end
        notifies :restart, "service[zabbix-agent]", :immediately
    end

    cookbook_file "/tmp/python-requests-aws_0.1.6_all.deb" do
        source "bins/python-requests-aws_0.1.6_all.deb"
        owner "root"
        mode 00444
    end

    package "requests-aws" do
        provider Chef::Provider::Package::Dpkg
        source "/tmp/python-requests-aws_0.1.6_all.deb"
        action :install
    end

    template "/usr/local/bin/zabbix_bucket_stats" do
        source "zabbix_bucket_stats.erb"
        owner "root"
        group "root"
        mode "00755"
        only_if do get_cached_head_node_names.include?(node['hostname']) end
    end

    cookbook_file "/usr/local/bin/zabbix_discover_buckets" do
        source "zabbix_discover_buckets"
        owner "root"
        mode "00755"
        only_if do get_cached_head_node_names.include?(node['hostname']) end
    end

end
