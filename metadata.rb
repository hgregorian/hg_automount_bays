name 'hg_automount_bays'
maintainer 'Heig Gregorian'
maintainer_email 'theheig@gmail.com'
license 'all_rights'
description 'Installs/Configures hg_automount_bays'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version '0.4.0'
depends 'filesystem', '~> 0.10.6'
depends 'logrotate', '~> 1.9'
depends 'systemd', '~> 2.1.2'
depends 'hg_sas3ircu'
depends 'hg_mergerfs'

supports 'centos'
supports 'redhat'
source_url 'https://github.com/hgregorian/hg_automount_bays' if defined?(:source_url)
issues_url 'https://github.com/hgregorian/hg_automount_bays/issues' if defined?(:issues_url)
