require "./spec_helper"

describe Maildir do
  describe "#initialize" do
    it "creates the tmp, new, and cur subdirectories by default" do
      maildir = temp_maildir
      Maildir::SUBDIRS.each do |sub|
        Dir.exists?(File.join(maildir.path, sub)).should be_true
      end
    end

    it "does not create subdirectories when create is false" do
      dir = File.join(Dir.tempdir, "maildir_nocreate_#{Process.pid}")
      FileUtils.rm_rf(dir)
      TEMP_MAILDIRS << dir
      Maildir.new(dir, false)
      Dir.exists?(File.join(dir, "new")).should be_false
    end

    it "ensures the path ends with a trailing slash" do
      temp_maildir.path.ends_with?("/").should be_true
    end
  end

  describe "#path helpers" do
    it "returns tmp, new, and cur paths" do
      maildir = temp_maildir
      maildir.tmp_path.should eq File.join(maildir.path, "tmp")
      maildir.new_path.should eq File.join(maildir.path, "new")
      maildir.cur_path.should eq File.join(maildir.path, "cur")
    end
  end

  describe "#add and #get" do
    it "writes a message into new and reads it back by key" do
      maildir = temp_maildir
      message = maildir.add("Hello, Crystal!")

      message.dir.should eq "new"
      maildir.get(message.key).data.should eq "Hello, Crystal!"
    end
  end

  describe "#list" do
    it "lists messages in new sorted by key" do
      maildir = temp_maildir
      3.times { |i| maildir.add("msg #{i}") }

      keys = maildir.list("new").map(&.key)
      keys.size.should eq 3
      keys.should eq keys.sort
    end

    it "moves messages from new to cur via process" do
      maildir = temp_maildir
      message = maildir.add("data")

      maildir.list("new").size.should eq 1
      message.process
      maildir.list("new").size.should eq 0
      maildir.list("cur").size.should eq 1
    end

    it "honors the limit option" do
      maildir = temp_maildir
      5.times { |i| maildir.add("msg #{i}") }

      maildir.list("new", {:limit => 2}).size.should eq 2
    end

    it "filters cur messages by flags" do
      maildir = temp_maildir
      message = maildir.add("data")
      message.process
      message.add_flag("S")
      message.add_flag("F")

      maildir.list("cur", {:flags => "FS"}).size.should eq 1
      maildir.list("cur", {:flags => "F"}).size.should eq 0
      maildir.list("cur", {:flags => ""}).size.should eq 0
    end

    it "raises ArgumentError for an unknown directory" do
      maildir = temp_maildir
      expect_raises(ArgumentError) { maildir.list("bogus") }
    end
  end

  describe "#delete" do
    it "removes the message file" do
      maildir = temp_maildir
      message = maildir.add("data")
      message.process

      maildir.delete(message.key)
      maildir.list("cur").size.should eq 0
    end
  end

  describe "#get_stale_tmp" do
    it "returns tmp messages older than the cutoff" do
      maildir = temp_maildir
      # add() moves messages out of tmp, so write one directly into tmp.
      message = Maildir::Message.new(maildir)
      maildir.serializer.dump("stale", message.path)

      maildir.get_stale_tmp(Time.utc + 1.hour).map(&.key).should contain message.key
      maildir.get_stale_tmp(Time.utc - 1.hour).should be_empty
    end
  end

  describe "comparison" do
    it "compares maildirs by path" do
      maildir = temp_maildir
      same = Maildir.new(maildir.path)
      (maildir <=> same).should eq 0
      maildir.should eq same
    end
  end

  describe "default serializer" do
    it "is shared across instances and overridable per instance" do
      maildir = temp_maildir
      maildir.serializer.should be_a Maildir::Serializer::Base

      custom = Maildir::Serializer::JSON.new
      maildir.serializer = custom
      maildir.serializer.should be custom
    end
  end
end
