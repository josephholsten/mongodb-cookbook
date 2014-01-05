class Chef
  class Resource::MongodbInstance < Resource
    include Poise
    actions(:enable)

    attribute(:configserver_nodes, kind_of: Array, default: [])
    attribute(:dbpath, kind_of: String, default: '/data')
    attribute(:logpath, kind_of: String, default: '/var/log/mongodb')
    attribute(:replicaset, kind_of: [Array, NilClass], default: nil)
    attribute(:service_action, kind_of: Array, default: [:enable, :start])
    attribute(:service_notifies, kind_of: Array, default: [])
    attribute(:mongodb_type, kind_of: String, default: 'mongod', callbacks: {
      'should be "mongod", "shard", "configserver" or "mongos"' => lambda {|type|
        ['mongod', 'shard', 'configserver', 'mongos'].include? type
      }}
    )

    attribute(:auto_configure_replicaset, kind_of: [TrueClass, FalseClass], default: lazy { node['mongodb']['auto_configure']['replicaset'] })
    attribute(:auto_configure_sharding, kind_of: [TrueClass, FalseClass], default: lazy { node['mongodb']['auto_configure']['sharding'] })
    attribute(:bind_ip, kind_of: String, default: lazy { node['mongodb']['config']['bind_ip'] })
    attribute(:cluster_name, kind_of: String, default: lazy { node['mongodb']['cluster_name'] })
    attribute(:config, kind_of: String, default: lazy { node['mongodb']['config'] })
    attribute(:dbconfig_file, kind_of: String, default: lazy { node['mongodb']['dbconfig_file'] })
    attribute(:dbconfig_file_template, kind_of: String, default: lazy { node['mongodb']['dbconfig_file_template'] })
    attribute(:init_dir, kind_of: String, default: lazy { node['mongodb']['init_dir'] })
    attribute(:init_script_template, kind_of: String, default: lazy { node['mongodb']['init_script_template'] })
    attribute(:is_replicaset, kind_of: String, default: lazy { node['mongodb']['is_replicaset'] })
    attribute(:is_shard, kind_of: String, default: lazy { node['mongodb']['is_shard'] })
    attribute(:mongodb_group, kind_of: String, default: lazy { node['mongodb']['group'] })
    attribute(:mongodb_user, kind_of: String, default: lazy { node['mongodb']['user'] })
    attribute(:port, kind_of: String, default: lazy { node['mongodb']['config']['port'] })
    attribute(:reload_action, kind_of: String, default: lazy { node['mongodb']['reload_action'] })
    attribute(:replicaset_name, kind_of: String, default: lazy { node['mongodb']['replicaset_name'] })
    attribute(:root_group, kind_of: String, default: lazy { node['mongodb']['root_group'] })
    attribute(:shard_name, kind_of: String, default: lazy { node['mongodb']['shard_name'] })
    attribute(:sharded_collections, kind_of: String, default: lazy { node['mongodb']['sharded_collections'] })
    attribute(:sysconfig_file, kind_of: String, default: lazy { node['mongodb']['sysconfig_file'] })
    attribute(:sysconfig_file_template, kind_of: String, default: lazy { node['mongodb']['sysconfig_file_template'] })
    attribute(:sysconfig_vars, kind_of: Hash, default: lazy { node['mongodb']['sysconfig'] })
    attribute(:template_cookbook, kind_of: String, default: lazy { node['mongodb']['template_cookbook'] })
    attribute(:ulimit, kind_of: String, default: lazy { node['mongodb']['ulimit'] })

    def init_file
      if node['mongodb']['apt_repo'] == 'ubuntu-upstart'
        init_file = ::File.join(init_dir, "#{name}.conf")
      else
        init_file = ::File.join(init_dir, name)
      end
    end

    def mode
      if node['mongodb']['apt_repo'] == 'ubuntu-upstart'
        mode = '0644'
      else
        mode = '0755'
      end
    end

    def replicaset_name
      if mongodb_type == 'shard'
        if replicaset.nil?
          replicaset_name = nil
        else
          # for replicated shards we autogenerate the replicaset name for each shard
          replicaset_name = "rs_#{replicaset['mongodb']['shard_name']}"
        end
      else
        # if there is a predefined replicaset name we use it,
        # otherwise we try to generate one using 'rs_$SHARD_NAME'
        begin
          replicaset_name = replicaset['mongodb']['replicaset_name']
        rescue
          replicaset_name = nil
        end
        if replicaset_name.nil?
          begin
            replicaset_name = "rs_#{replicaset['mongodb']['shard_name']}"
          rescue
            replicaset_name = nil
          end
        end
      end
      return replicaset_name
    end

    def provides
      if mongodb_type == 'mongos'
        'mongos'
      else
        'mongod'
      end
    end

    def configserver
      if mongodb_type == 'mongos'
        configserver_nodes.collect do |n|
          hostname = n['mongodb']['configserver_url'] || n['fqdn']
          port = n['mongodb']['config']['port']
          "#{hostname}:#{port}"
        end.sort.join(',')
      end
    end

    def config
      raw_config = super
      if mongodb_type == 'mongos'
        raw_config.delete('dbpath')
        raw_config[:configdb] ||= configdb
      end
      raw_config
    end

    def shard_nodes
      raise "shard_nodes should only be accessed from mongos instances" unless mongodb_type == 'mongos' && auto_configure_sharding
      search(
        :node,
        "mongodb_cluster_name:#{new_resource.cluster_name} AND \
         mongodb_is_shard:true AND \
         chef_environment:#{node.chef_environment}"
      )
    end

    def replicaset_nodes
      raise "replicaset_nodes should only be accessed from replicaset instances" unless is_replicaset
      search(
        :node,
        "mongodb_cluster_name:#{new_resource.replicaset['mongodb']['cluster_name']} AND \
         mongodb_is_replicaset:true AND \
         mongodb_shard_name:#{new_resource.replicaset['mongodb']['shard_name']} AND \
         chef_environment:#{new_resource.replicaset.chef_environment}"
      )
    end

    private
    def configdb
      configserver_nodes.collect do |n|
        host = n['mongodb']['configserver_url'] || n['fqdn']
        port = n['mongodb']['config']['port']
        "#{host}:#{port}"
      end.sort.join(",")
    end
  end

  class Provider::MongodbInstance < Provider
    include Poise::Provider
    def action_enable
      converge_by("enable mongodb instance #{new_resource.name}") do
        notifying_block do

          # default file
          template new_resource.sysconfig_file do
            cookbook new_resource.template_cookbook
            source new_resource.sysconfig_file_template
            group new_resource.root_group
            owner 'root'
            mode '0644'
            variables(
              :sysconfig => new_resource.sysconfig_vars
            )
            # notifies new_resource.reload_action, 'service[#{new_resource.name}]'
          end

          # config file
          template new_resource.dbconfig_file do
            cookbook new_resource.template_cookbook
            source new_resource.dbconfig_file_template
            group new_resource.root_group
            owner 'root'
            mode '0644'
            variables(
              :config => new_resource.config
            )
            # notifies new_resource.reload_action, 'service[#{new_resource.name}]'
          end

          # log dir [make sure it exists]
          directory new_resource.logpath do
            owner new_resource.mongodb_user
            group new_resource.mongodb_group
            mode '0755'
            action :create
            recursive true
          end

          unless new_resource.mongodb_type == 'mongos'
            # dbpath dir [make sure it exists]
            directory new_resource.dbpath do
              owner new_resource.mongodb_user
              group new_resource.mongodb_group
              mode '0755'
              action :create
              recursive true
            end
          end

          # init script
          template new_resource.init_file do
            cookbook new_resource.template_cookbook
            source new_resource.init_script_template
            group new_resource.root_group
            owner 'root'
            mode new_resource.mode
            variables(
              :provides =>       new_resource.provides,
              :sysconfig_file => new_resource.sysconfig_file,
              :ulimit =>         new_resource.ulimit,
              :bind_ip =>        new_resource.bind_ip,
              :port =>           new_resource.port
            )
            # notifies new_resource.reload_action, 'service[#{new_resource.name}]'
          end

          # service
          service new_resource.name do
            if new_resource.using_upstart?
              provider Chef::Provider::Service::Upstart
            end
            supports :status => true, :restart => true
            action new_resource.service_action
            new_resource.service_notifies.each do |service_notify|
              notifies :run, service_notify
            end
            if new_resource.is_replicaset && new_resource.auto_configure_replicaset
              notifies :create, 'ruby_block[config_replicaset]'
            end
            if new_resource.mongodb_type == 'mongos' && new_resource.auto_configure_sharding
              notifies :create, 'ruby_block[config_sharding]', :immediately
            end
            if new_resource.name == 'mongodb'
              # we don't care about a running mongodb service in these cases, all we need is stopping it
              ignore_failure true
            end
          end

          # replicaset
          ruby_block 'config_replicaset' do
            block do
              MongoDB.configure_replicaset(new_resource.replicaset, new_resource.replicaset_name, new_resource.replicaset_nodes)
            end
            action :nothing
          end

          # sharding
          ruby_block 'config_sharding' do
            block do
              MongoDB.configure_shards(node, new_resource.shard_nodes)
              MongoDB.configure_sharded_collections(node, new_resource.sharded_collections)
            end
            action :nothing
          end
        end
      end
    end
  end
end
