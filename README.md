# hg_automount_bays cookbook

All things needed to automatically mount bays.

## Supported Platforms

* CentOS 7

## Attributes

| Key | Type | Description | Default |
| --- | ---- | ----------- | ------- |
|`node['hg_automount_bays']['app_path']`|String|Path for application|'/opt/automount_bays'|

## Usage

Regarding justification of current `udev` rule configuration, please see [this bugzilla](https://bugzilla.redhat.com/show_bug.cgi?id=871074) for more information.

### hg_automount_bays::default

Include `hg_automount_bays`:

```ruby
include_recipe 'hg_automount_bays::default'
```

## License and Authors

Author:: Heig Gregorian (theheig@gmail.com)
