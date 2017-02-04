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
  options 'defaults,nofail,ro'
  action [:create, :enable, :mount]
  only_if { ::File.readlines('/proc/mounts').grep(/\s+#{dummy_srcmount_path}\s+/).empty? }
end

## Install mergerfs package
mergerfs_package '2.19.0'

## Install 'mergerfs-tools
mergerfs_tools '/opt/mergerfs-tools/bin' do
  commit 'master'
  symlink true
  symlink_path '/usr/local/sbin'
end

## Configure 'mergerfs' pool
mergerfs_pool '/storage' do
  srcmounts [
    dummy_srcmount_path,
    File.join(node['hg_automount_bays']['app_config']['device_helper']['mount_root'],
              "*-#{node['hg_automount_bays']['app_config']['device_helper']['suffix_data']}")
  ]
  options %w(defaults allow_other direct_io use_ino category.create=mfs moveonenospc=true minfreespace=20G fsname=mergerfsPool)
  automount true
end
