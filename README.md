# hg_automount_bays cookbook

All things needed to automatically mount bays. (needs real description and actual usage)

## Supported Platforms

* CentOS/RHEL 7

## Attributes

| Key | Type | Description | Default |
| --- | ---- | ----------- | ------- |
|`node['hg_automount_bays']['app_path']`|String|Path for application|'/opt/automount_bays'|
|`node['hg_automount_bays']['app_config']['device_helper']['number_of_bays']`|Integer|Total number of bays available|24|
|`node['hg_automount_bays']['app_config']['device_helper']['parity_bays']`|Array|Descript|[1,2,3,4]|
|`node['hg_automount_bays']['app_config']['device_helper']['mount_root']`|String|Path where individual mount points will appear|'/mnt'|
|`node['hg_automount_bays']['app_config']['device_helper']['suffix_parity']`|String|Append to mount points of bays designated for parity usage|'parity'|
|`node['hg_automount_bays']['app_config']['device_helper']['suffix_data']`|String|Append to mount points of bays designated for data usage|'data'|
|`node['hg_automount_bays']['app_config']['device_helper']['mergerfs_support']`|Boolean|Perform mergerfs specific tasks|true|
|`node['hg_automount_bays']['app_config']['device_helper']['mount_options']`|Array|Mount options for individual drives|%w(defaults nofail errors=remount-ro)|
|`node['hg_automount_bays']['app_config']['device_helper']['auto_format']`|Boolean|Automatically format drives placed in bays|true|
|`node['hg_automount_bays']['app_config']['device_helper']['log_level']`|Symbol|Set logging level|:info|
|`node['hg_automount_bays']['app_config']['mergerfs']['dummy_srcmount_path']`|String|Path to mount read-only srcmount|'/opt/ro_srcmount'|

## Usage

Regarding justification of current `udev` rule configuration, please see [this bugzilla](https://bugzilla.redhat.com/show_bug.cgi?id=871074) for more information.

### hg_automount_bays::default

Include `hg_automount_bays`:

```ruby
include_recipe 'hg_automount_bays::default'
```

## License and Authors

Author:: Heig Gregorian (theheig@gmail.com)
