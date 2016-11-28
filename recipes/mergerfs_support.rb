#
# Cookbook Name:: hg_automount_bays
# Recipe:: mergerfs_support
#
# Copyright (c) 2016 Heig Gregorian, All Rights Reserved.

## In the case that mergerfs support is desired, mergerfs package, tools, and configuration
## needs to be in place before bays (srcmounts) are mounted.  The mergerfs filesystem will not initialize
## without any srcmounts, therefore, create and mount a dummy read-only srcmount.
filesystem 'mergerfs_dummy_srcmount' do
  fstype 'ext4'
  device '/dev/loop10'
  file '/opt/mergerfs_dummy_srcmount'
  size '1'
  mount '/mnt/ro_srcmount'
  options 'defaults,ro'
  action [:create, :enable, :mount]
  only_if { ::File.readlines('/proc/mounts').grep(%r{\s+/mnt/ro_srcmount\s+}).empty? }
end

include_recipe 'hg_mergerfs::default'
