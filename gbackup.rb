require "fileutils"


GSUTIL = "/home/carl/bin/gsutil/gsutil"
TMPDIR = "/tmp"
DEST_BUCKET = "gs://backup_relevantgames_cog2"

exit unless ARGV.length >= 2

COMMAND = ARGV[0]
REPO_PATH = ARGV[1]
NEW_REVISION = ARGV[2].to_i

MY_PATH = File.expand_path(File.dirname(__FILE__))
LAST_REVISION = `cat #{MY_PATH}/.lastrevision`.to_i

TMP_FILENAME = "backup.#{Time.now.localtime.strftime("%Y-%m-%d")}"

ENV['AWS_CREDENTIAL_FILE'] = "#{MY_PATH}/.boto"

def update_last_revision
  `echo #{NEW_REVISION} > #{MY_PATH}/.lastrevision`
end

def gsutil_delete file
  system "#{GSUTIL} rm #{file}"
end

def purge ignore
  files = %x[#{GSUTIL} ls #{DEST_BUCKET}]
  files = files.split("\n")

  files.each do |file|
    unless ignore.include? file.sub(/#{DEST_BUCKET}\//, "")
      gsutil_delete file
    end
  end
end

def upload file_path
  raise "upload failed" unless system "#{GSUTIL} cp #{file_path} #{DEST_BUCKET}"
end

def replace_slashes path
  path.sub(/\//, '').gsub(/\//, '_')
end

def incremental_backup from_rev, to_rev, repo_dir
  incremental_backup_cmd = 'svnadmin dump --quiet --revision %d:%d --incremental "%s" > "%s"'
  raise "incremental backup failed" unless system incremental_backup_cmd % [from_rev, to_rev, repo_dir, TMP_FILENAME]
end

def full_backup repo_dir
  full_backup_cmd = 'svnadmin hotcopy "%s" "%s"'
  raise "hotcopy failed" unless system full_backup_cmd % [repo_dir, TMP_FILENAME]
end

def compress_to dest_name
  compress_cmd = "tar -czf '%s' '%s'"
  raise "compress failed" unless system compress_cmd % [dest_name, TMP_FILENAME]
end

def clean_up
  FileUtils.remove_entry_secure TMP_FILENAME, true
  FileUtils.rm $backup_name, :force => true
end

# we are working in /tmp
FileUtils.cd TMPDIR

at_exit { clean_up }

$backup_name = ""
post_commit = false
if COMMAND == "post-commit"
  $backup_name = "incremental.%s.%d_%d.svndump.tgz" % [replace_slashes(REPO_PATH), LAST_REVISION, NEW_REVISION]
  incremental_backup LAST_REVISION, NEW_REVISION, REPO_PATH
  post_commit = true
else
  $backup_name = "full.%s.#{Time.now.localtime.strftime("%Y-%m-%d")}.hotcopy.tgz" % [replace_slashes(REPO_PATH)]
  full_backup REPO_PATH
end

compress_to $backup_name
upload $backup_name

purge [$backup_name] unless post_commit

clean_up

update_last_revision if post_commit
