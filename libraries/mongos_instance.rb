require_relative 'instance'

class Chef
  class Resource::MongodbMongosInstance < Resource::MongodbInstance
    def replicaset_name
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
      return replicaset_name
    end

    def config
      raw_config = super
      raw_config.delete('dbpath')
      raw_config[:configdb] ||= configdb
      raw_config
    end

    def shard_nodes
      search(
        :node,
        "mongodb_cluster_name:#{new_resource.cluster_name} AND \
         mongodb_is_shard:true AND \
         chef_environment:#{node.chef_environment}"
      )
    end

    def provides
      "mongos"
    end

    def should_configure_sharding?
      auto_configure_sharding
    end

    def configdb
      configserver_nodes.collect do |n|
        host = n['mongodb']['configserver_url'] || n['fqdn']
        port = n['mongodb']['config']['port']
        "#{host}:#{port}"
      end.sort.join(",")
    end
  end
  class Provider::MongodbMongosInstance < Provider::MongodbInstance
    def configure_sharding
      @configure_sharding ||= ruby_block "config_sharding" do
        block do
          MongoDB.configure_shards(node, new_resource.shard_nodes)
          MongoDB.configure_sharded_collections(node, new_resource.sharded_collections)
        end
        only_if { new_resource.should_configure_sharding? }
        action :nothing
      end
    end
    def ensure_dbpath
      # nop, dbpath is unused for mongos
    end
  end
end
