#
# Cookbook Name:: hg_automount_bays
# Recipe:: mergerfs_support
#
# Copyright (c) 2016 Heig Gregorian, All Rights Reserved.

## In the case that mergerfs support is desired, mergerfs package, tools, and configuration
## needs to be in place before bays (srcmounts) are mounted.  The mergerfs filesystem will not initialize
## without any srcmounts, therefore, create and mount a dummy read-only srcmount.
dummy_srcmount_path = node['hg_automount_bays']['app_config']['mergerfs']['dummy_srcmount_path']
filesystem 'mergerfs_dummy_srcmount' do
  fstype 'ext4'
  device '/dev/loop10'
  file '/opt/mergerfs_dummy_srcmount.file'
  size '1'
  mount dummy_srcmount_path
  options 'defaults,ro'
  action [:create, :enable, :mount]
  only_if { ::File.readlines('/proc/mounts').grep(/\s+#{dummy_srcmount_path}\s+/).empty? }
end

include_recipe 'hg_mergerfs::default'
