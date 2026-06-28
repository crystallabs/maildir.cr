require "./spec_helper"

describe Maildir::Message do
  describe "lifecycle" do
    it "is created in tmp, then moved to new on write" do
      maildir = temp_maildir
      message = Maildir::Message.new(maildir)
      message.dir.should eq "tmp"

      message.write("body")
      message.dir.should eq "new"
      File.exists?(message.path).should be_true
    end

    it "moves new -> cur on process, adding the default info" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process
      message.dir.should eq "cur"
      message.info.should eq Maildir::Message::INFO
    end

    it "raises when writing a message that already has a key" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process
      expect_raises(Exception, /Can only write/) { message.write("again") }
    end

    it "raises when constructed with an invalid state" do
      maildir = temp_maildir
      expect_raises(ArgumentError) { Maildir::Message.new(maildir, "bogus/key") }
    end
  end

  describe "flags" do
    it "adds, queries, and removes single flags" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process

      message.seen?.should be_false
      message.add_flag("S")
      message.seen?.should be_true
      message.flagged?.should be_false

      message.add_flag("F")
      message.flagged?.should be_true
      message.remove_flag("F")
      message.flagged?.should be_false
      message.seen?.should be_true
    end

    it "keeps flags uppercase, sorted, and unique" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process

      message.add_flag("s")
      message.add_flag("FsS")
      message.flags.should eq ["F", "S"]
    end

    it "supports adding arbitrary-letter flags" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process
      message.add_flag("X")
      message.flags.should contain "X"
    end

    it "removes multiple flags at once" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process
      message.add_flag("DPR")
      message.remove_flag("DPR")
      message.flags.should be_empty
    end

    it "is a no-op when removing with a blank string" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process
      message.add_flag("S")
      message.remove_flag("")
      message.flags.should eq ["S"]
    end

    it "raises when setting info on a non-cur message" do
      maildir = temp_maildir
      message = maildir.add("body") # still in new
      expect_raises(Exception, /Can only set info/) { message.info = "2,S" }
    end
  end

  describe "#data" do
    it "raises File::NotFoundError when the file is gone" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.destroy
      expect_raises(File::NotFoundError) { message.data }
    end
  end

  describe "file system metadata" do
    it "exposes mtime as Time" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.mtime.should be_a Time
    end

    it "returns false for metadata of a missing file" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.destroy
      message.mtime.should be_false
    end

    it "updates times with utime" do
      maildir = temp_maildir
      message = maildir.add("body")
      past = Time.utc - 1.day
      message.utime(past, past)
      mtime = message.mtime
      mtime.should be_a Time
      mtime.as(Time).to_unix.should be_close(past.to_unix, 2)
    end
  end

  describe "#destroy" do
    it "returns false when the file is already gone" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.destroy
      message.destroy.should be_false
    end
  end

  describe "comparison" do
    it "compares two handles to the same message as equal" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process
      copy = maildir.get(message.key)
      message.should eq copy
      (message <=> copy).should eq 0
    end
  end
end
