#
# Cookbook Name:: hg_automount_bays
# Recipe:: default
#
# Copyright (c) 2016 Heig Gregorian, All Rights Reserved.

include_recipe 'hg_sas3ircu::sas3ircu'

if node['hg_automount_bays']['app_config']['device_helper']['mergerfs_support']
  include_recipe 'hg_automount_bays::mergerfs_support'
end

package 'dependencies' do
  package_name %w(ruby)
end

gem_package 'mixlib-shellout'

## Setup application directory structure
app_dir = node['hg_automount_bays']['app_path']
bin_dir = File.join(app_dir, 'bin')
etc_dir = File.join(app_dir, 'etc')
%w(bin etc var/log).each do |dir|
  directory File.join(app_dir, dir) do
    owner 'root'
    group 'root'
    mode '0755'
    recursive true
  end
end

## Assign lists for bay designation
bays = (1..node['hg_automount_bays']['app_config']['device_helper']['number_of_bays']).to_a
parity_bays = node['hg_automount_bays']['app_config']['device_helper']['parity_bays'].map(&:to_i)

## Create fstab entries for all bays
bays.each do |id|
  bay_id = id.to_s.rjust(2, '0')
  suffix = if parity_bays.include?(bay_id.to_i)
             node['hg_automount_bays']['app_config']['device_helper']['suffix_parity']
           else
             node['hg_automount_bays']['app_config']['device_helper']['suffix_data']
           end
  mount File.join(node['hg_automount_bays']['app_config']['device_helper']['mount_root'], "#{bay_id}-#{suffix}") do
    device "/dev/disk/by-bay/#{bay_id}"
    fstype 'auto'
    options node['hg_automount_bays']['app_config']['device_helper']['mount_options']
    dump 0
    pass 2
    action :enable
  end
end

## Deploy 'device_helper' to app/bin
cookbook_file File.join(bin_dir, 'device_helper.rb') do
  source 'app/bin/device_helper.rb'
  mode '0755'
  owner 'root'
  group 'root'
end

## Deploy configuration file for 'device_helper' to app/etc
file File.join(etc_dir, 'device_helper.yml') do
  content JSON.parse(node['hg_automount_bays']['app_config']['device_helper'].to_json).to_yaml
end

## Setup logrotate for 'device_helper' logs
logrotate_app 'device_helper-log' do
  path File.join(app_dir, 'var/log/device_helper.log')
  frequency 'weekly'
  rotate 4
  create '644 root root'
end

## Deploy system.unit for mounting bays
systemd_service 'mount-bay@' do
  description 'Mount drive bay and optionally add to mergerfs filesystem'
  service do
    type 'oneshot'
    timeout_start_sec node['hg_automount_bays']['app_config']['device_helper']['auto_format'] ? '120' : '10'
    exec_start '/opt/automount_bays/bin/device_helper.rb --add %I'
  end
end

## Deploy system.unit for unmounting bays
systemd_service 'unmount-bay@' do
  description 'Unmount drive bay and optionally remove from mergerfs filesystem'
  service do
    type 'oneshot'
    timeout_start_sec '30'
    exec_start '/opt/automount_bays/bin/device_helper.rb --remove %I'
  end
end

## Udev rule for handling devices connected to HBA
systemd_udev_rules '99-automount-bays' do
  rules [
    [
      {
        'key' => 'KERNEL',
        'operator' => '!=',
        'value' => 'sd*[!0-9]'
      },
      {
        'key' => 'ENV{DEVTYPE}',
        'operator' => '!=',
        'value' => 'disk'
      },
      {
        'key' => 'GOTO',
        'operator' => '=',
        'value' => 'exit_rule'
      }
    ],
    [
      {
        'key' => 'IMPORT{program}',
        'operator' => '=',
        'value' => "#{File.join(bin_dir, 'device_helper.rb')} %k"
      }
    ],
    [
      {
        'key' => 'SYMLINK',
        'operator' => '+=',
        'value' => 'disk/by-bay/$env{BAY_ID}'
      }
    ],
    [
      {
        'key' => 'ACTION',
        'operator' => '==',
        'value' => 'add'
      },
      {
        'key' => 'ENV{BAY_ID}',
        'operator' => '!=',
        'value' => ''
      },
      {
        'key' => 'PROGRAM',
        'operator' => '=',
        'value' => '/usr/bin/systemd-escape -p --template=mount-bay@.service $env{BAY_ID}'
      },
      {
        'key' => 'ENV{SYSTEMD_WANTS}',
        'operator' => '+=',
        'value' => '%c'
      }
    ],
    [
      {
        'key' => 'ACTION',
        'operator' => '==',
        'value' => 'remove'
      },
      {
        'key' => 'RUN',
        'operator' => '+=',
        'value' => '/bin/systemctl --no-block start unmount-bay@$env{BAY_ID}.service'
      }
    ],
    [
      {
        'key' => 'LABEL',
        'operator' => '=',
        'value' => 'exit_rule'
      }
    ]
  ]
  action :create
end

include_recipe 'hg_sas3ircu::mpt3sas'
