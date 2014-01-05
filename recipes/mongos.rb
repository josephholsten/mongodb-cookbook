#
# Cookbook Name:: mongodb
# Recipe:: mongos
#
# Copyright 2011, edelight GmbH
# Authors:
#       Markus Korn <markus.korn@edelight.de>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "mongodb::install"
include_recipe "mongodb::mongo_gem"

service 'mongodb' do
  action [:disable, :stop]
end

configserver_nodes = search(
  :node,
  "mongodb_cluster_name:#{node['mongodb']['cluster_name']} AND \
   mongodb_is_configserver:true AND \
   chef_environment:#{node.chef_environment}"
)

if configserver_nodes.length != 1 and configsrv.length != 3
  Chef::Log.error("Found #{configsrv.length} configserver, need either one or three of them")
  raise "Wrong number of configserver nodes"
end

mongodb_mongos_instance "mongos" do
  configserver_nodes configserver_nodes
  action [:enable, :start]
end
