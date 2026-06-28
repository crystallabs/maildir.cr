require "spec"
require "file_utils"
require "../src/maildir.cr"

# Track temp maildirs so we can clean them all up after the suite runs.
TEMP_MAILDIRS = [] of String

# Create a fresh, isolated maildir in a unique temp directory.
def temp_maildir
  dir = File.join(Dir.tempdir, "maildir_test_#{Process.pid}_#{TEMP_MAILDIRS.size}")
  FileUtils.rm_rf(dir)
  TEMP_MAILDIRS << dir
  Maildir.new(dir)
end

# Create the subdir tree:
# | INBOX
# |-- a
# |   |-- x
# |   |-- y
# |-- b
def setup_subdirs(maildir)
  %w(a b a.x a.y).each do |x|
    Maildir.new(File.join(maildir.path, ".#{x}"))
  end
end

Spec.after_suite do
  TEMP_MAILDIRS.each { |dir| FileUtils.rm_rf(dir) }
  # Reset the global default serializer in case a spec changed it.
  Maildir.serializer = Maildir::Serializer::Base.new
end
