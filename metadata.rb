name 'hg_automount_bays'
maintainer 'Heig Gregorian'
maintainer_email 'theheig@gmail.com'
license 'all_rights'
description 'Installs/Configures hg_automount_bays'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version '0.2.0'
depends 'systemd', '~> 2.1.2'
depends 'hg_sas3ircu'
depends 'hg_mergerfs'
gem 'mixlib-shellout'

supports 'centos'
supports 'redhat'
