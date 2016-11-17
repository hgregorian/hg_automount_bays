#
# Cookbook Name:: hg_automount_bays
# Attribute:: default
#
# Copyright (c) 2016 Heig Gregorian, All Rights Reserved.

## Native attributes
default['hg_automount_bays']['app_path'] = '/opt/automount_bays'
default['hg_automount_bays']['app_config']['device_helper']['number_of_bays'] = 24
default['hg_automount_bays']['app_config']['device_helper']['parity_bays'] = (1..4).to_a
default['hg_automount_bays']['app_config']['device_helper']['mount_root'] = '/mnt'
default['hg_automount_bays']['app_config']['device_helper']['suffix_parity'] = 'parity'
default['hg_automount_bays']['app_config']['device_helper']['suffix_data'] = 'data'
default['hg_automount_bays']['app_config']['device_helper']['mergerfs_support'] = false

## Mergerfs attributes
default['hg_mergerfs']['volumes'] = {
  '/storage' => {
    'mount_points' => '/mnt/*-data',
    'options' => ['category.create=eplfs', 'moveonenospc=true', 'defaults', 'allow_other', 'minfreespace=20G', 'fsname=mergerfsPool']
  }
}
