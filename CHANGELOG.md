# 0.2.0
- in `device_helper.rb`, depending on symlinks in `/dev/disk` was a horrible idea; now sourcing WWN/WWID's using a more reliable method
- minor tweak to udev rule
- determine if device is eligable to be mounted based on formatting; remediate if desired

# 0.1.0
Initial release

# 0.0.0

Initial creation of hg_automount_bays