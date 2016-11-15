#!/bin/env ruby

require 'fileutils'
require 'open3'
require 'optparse'
require 'yaml'

DRY_RUN = false

## Setup some init variables
program_name = File.basename($PROGRAM_NAME, File.extname($PROGRAM_NAME))

config_path = File.join(__dir__, '../etc', "#{program_name}.yml")
app_config = YAML.load_file(config_path)
@options = app_config.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }

def sanitize_key(string)
  string.downcase!
  # string.gsub!(/\(.*/, '')
  string.gsub!(/[^a-z\s].*/, '')
  string.gsub!(/[^a-z\s]/, '')
  string.strip!
  string.gsub!(/\s/, '_')
  string.to_sym
end

def hba_info
  out = `/root/sas3ircu 0 display`

  sections = out.scan(/^Device.*?\n(.*?)(?:\n\n|\n---*?)/m).flatten.map { |x| x.split("\n") }

  sections.map! do |section|
    Hash[*section.map do |entry|
      kv_pairs = entry.split(':').map(&:strip)
      kv_pairs[0] = sanitize_key(kv_pairs[0])
      kv_pairs
    end.flatten]
  end

  ## Populate hashes with WWN (worldwide name AKA WWID - worldwide ID)
  sections.each do |section|
    ## Sanitize drive "state" flag
    section[:state] = section[:state].match(/\((.*?)\)/)[1]

    ## Provide a reasonable physical bay ID (1-24, left to right, top to bottom)
    section[:bay_id] = (1..24).to_a.each_slice(4).to_a.map(&:reverse).flatten[section[:slot].to_i]

    ## Convert provided GUID to a valid WWN/WWID
    section[:wwn] = section[:guid].scan(/.{1,4}/).reverse.join.sub(/^0*/, '')

    ## Scan for any partitions and create entries accordingly
    begin
      section[:dev_path] = File.realpath("/dev/disk/by-id/wwn-0x#{section[:wwn]}")
      Dir.glob("/dev/disk/by-id/wwn-0x#{section[:wwn]}-part*").each do |part_path|
        part = part_path.match(/.*-(part\d+)/)[1]
        section[:"#{part}_path"] = File.realpath(part_path)
      end
    rescue => e
      abort "Something unexpected happened: #{e}"
    end
  end
  sections
end

def run_command(cmd, abort_on_error = false)
  cmd = cmd.join(' ') if cmd.is_a?(Array)
  printf "%s\n", cmd
  return if DRY_RUN
  _stdin, stdout_err, wait_thr = Open3.popen2e(cmd)
  exit_status = wait_thr.value

  stdout_err.readlines.each do |l|
    puts l.chomp
  end

  abort("Error running #{cmd}") if !exit_status.success? && abort_on_error
  exit_status.success?
end

def parity_bay?(bay)
  @options[:parity_bays].include? bay.to_i
end

def mergerfs_ctl(cmd)
  return unless @options[:mergerfs_support]
  run_command(cmd)
end

def zero_padding(num, padding)
  num.to_s.rjust(padding.to_i, '0')
end

begin
  opts = OptionParser.new do |o|
    o.banner = "Usage: #{program_name} [--add|--remove] [options]"
    o.separator 'Mandatory flags:'
    o.on('-a', '--add BAY_ID', String,
         "ex. '15'") do |opt|
      @options[:add] = opt.to_i
    end
    o.on('-r', '--remove BAY_ID', String,
         "ex. '15'") do |opt|
      @options[:remove] = opt.to_i
    end
    o.parse!(ARGV)
  end
rescue OptionParser::InvalidOption, OptionParser::MissingArgument
  puts $ERROR_INFO.to_s
  puts opts
  exit(1)
end

p @options

if ARGV[0] =~ /^sd[a-z]+\d+/
  lookup_dev = ARGV[0].sub(/\d+$/, '')
  result = hba_info.select { |section| section[:dev_path] =~ /#{lookup_dev}/ }[0]

  ## Print environment variables for use with udev
  if result
    result.each do |k, v|
      value = v =~ /\s/ ? "'#{v}'" : v
      puts "#{k.upcase}=#{value}"
    end
    exit(0)
  else
    puts "The device '#{lookup_dev}' is not managed by HBA."
    exit(1)
  end
end

if @options[:add]
  ## Store bay_id
  bay_id = @options[:add]

  ## Abort if the bay_id is not present as 'by-bay' symlink (very improbable)
  abort "Nothing found in bay '#{bay_id}'..." unless File.exist?("/dev/disk/by-bay/#{bay_id}")

  ## Define mount point based on whether or not it has been designated as a parity bay
  mount_point = if parity_bay?(bay_id)
                  File.join(@options[:mount_root], "#{zero_padding(bay_id, 2)}-#{@options[:suffix_parity]}")
                else
                  File.join(@options[:mount_root], "#{zero_padding(bay_id, 2)}-#{@options[:suffix_data]}")
                end

  ## Create mount point and mount
  FileUtils.mkdir_p(mount_point)
  run_command("/usr/bin/mount /dev/disk/by-bay/#{bay_id} #{mount_point}")

  ## Add to merger volume if not in a parity bay
  mergerfs_ctl("/usr/local/sbin/mergerfs.ctl -m /storage add path #{mount_point}") unless parity_bay?(bay_id)
end

if @options[:remove]
  ## Pad bay_id with 0, i.e. 3 => 03, 20 => 20, etc.
  bay_id = zero_padding(@options[:remove], 2)

  ## Since it doesn't matter if this is a parity or data bay, look for either
  dirs = Dir.glob(File.join(@options[:mount_root], "#{bay_id}-*"))

  ## Something is horribly wrong if a bay_id matches multiples (implies that mount points exist for both parity and data)
  abort "Too many matches for removal! #{dirs}" if dirs.length > 1

  ## Store single match as mount point
  mount_point = dirs[0]

  ## This is precautionary as there's no reason to believe, at this time,
  ## that a bay_id, designated for parity, could've been mounted as a data mount
  mergerfs_mount_point = File.join(@options[:mount_root], "#{bay_id}-#{@options[:suffix_data]}")
  mergerfs_ctl("/usr/local/sbin/mergerfs.ctl -m /storage remove path #{mergerfs_mount_point}")

  ## Unmount and clean-up mount point
  unless mount_point.empty?
    run_command("/usr/bin/umount -l #{mount_point}")
    FileUtils.rm_rf(mount_point)
  end
end

exit(0)
