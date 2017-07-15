require "spec"
require "../src/maildir.cr"

# Create a reusable maildir
def temp_maildir
  dir= "/tmp/maildir_test"
  if File.exists? dir
    raise "Directory #{dir} already exists; please remove before running the test"
  end
  m= Maildir.new dir
  raise "Missing maildir!" unless m
  m
end

# create the subdir tree:
# | INBOX
# |-- a
# | |-- x
# | |-- y
# |-- b
def setup_subdirs(maildir)
  %w(a b a.x a.y).each do |x|
    Maildir.new(File.join(maildir.path, ".#{x}"))
  end
end
