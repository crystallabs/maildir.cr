require "spec"
require "file_utils"
require "../src/maildir.cr"

# Track temp maildirs so we can clean them all up after the suite runs.
TEMP_MAILDIRS = [] of String

# A serializer that records how often it flushed a message to disk.
class CountingSerializer < Maildir::Serializer::Base
  getter syncs = 0

  protected def sync(file : File) : Nil
    @syncs += 1
    super
  end
end

# Create a fresh, isolated maildir in a unique temp directory.
def temp_maildir
  dir = File.join(Dir.tempdir, "maildir_test_#{Process.pid}_#{TEMP_MAILDIRS.size}")
  FileUtils.rm_rf(dir)
  TEMP_MAILDIRS << dir
  Maildir.new(dir)
end

Spec.after_suite do
  TEMP_MAILDIRS.each { |dir| FileUtils.rm_rf(dir) }
  # Reset the global settings in case a spec changed them.
  Maildir.serializer = Maildir::Serializer::Base.new
  Maildir.fsync = true
end
