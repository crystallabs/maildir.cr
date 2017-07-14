require "spec"
require "../src/maildir.cr"

# Create a reusable maildir
def temp_maildir
  m= Maildir.new("/tmp/maildir_test")
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
