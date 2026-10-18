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

    it "keeps the flags of a message which is processed again" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process
      message.add_flag("S")
      key = message.key

      message.process.should eq key
      message.key.should eq key
      message.flags.should eq ["S"]
      maildir.list("cur").map(&.key).should eq [key]
    end

    it "refuses to process a message which is still in tmp" do
      maildir = temp_maildir
      message = Maildir::Message.new(maildir)
      maildir.serializer.dump("body", message.path)

      expect_raises(Exception, /Can only process/) { message.process }
      message.dir.should eq "tmp"
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

    it "raises ArgumentError, not IndexError, for a malformed key" do
      maildir = temp_maildir
      expect_raises(ArgumentError, /Key must be/) { Maildir::Message.new(maildir, "no-separator") }
      expect_raises(ArgumentError, /Key must be/) { Maildir::Message.new(maildir, "new/") }
    end

    it "round-trips keys of new messages without a stray colon" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.info.should be_nil
      message.key.should_not contain ':'
      maildir.get(message.key).filename.should eq message.filename
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

    it "treats regexp metacharacters in remove_flag as literal flags" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process
      message.add_flag("SF")

      # "[A-Z]" used to be interpolated into a regexp and wipe every flag.
      message.remove_flag("[A-Z]")
      message.flags.should eq ["F", "S"]
    end

    it "accepts a String or an Array for flags=, add_flag and remove_flag" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process

      message.flags = "sf"
      message.flags.should eq ["F", "S"]
      message.add_flag(["r", "T"])
      message.flags.should eq ["F", "R", "S", "T"]
      message.remove_flag(["f", "t"])
      message.flags.should eq ["R", "S"]
    end

    it "returns the message's key from the flag mutators" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process

      message.add_flag("S").should eq message.key
      message.remove_flag("S").should eq message.key
      message.remove_flag("").should eq message.key
    end

    it "provides a predicate and a bang method for every standard flag" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process

      message.passed?.should be_false
      message.replied?.should be_false
      message.trashed?.should be_false
      message.draft?.should be_false

      message.passed!
      message.replied!
      message.seen!
      message.trashed!
      message.draft!
      message.flagged!

      message.passed?.should be_true
      message.replied?.should be_true
      message.trashed?.should be_true
      message.draft?.should be_true
      message.flags.should eq Maildir::Message::FLAG_NAMES.values.to_a.sort
    end

    it "only strips the leading info marker when reading flags" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.process
      # A non-standard info must not be rewritten from the middle
      message.info = "3,X2,Y"
      message.flags.should eq ["3", ",", "X", "2", ",", "Y"]
    end
  end

  describe "#rewrite" do
    it "replaces the contents in place, keeping the key" do
      maildir = temp_maildir
      message = maildir.add("first")
      message.process
      key = message.key

      message.rewrite("second").should eq key
      message.key.should eq key
      message.data.should eq "second"
      maildir.list("cur").map(&.key).should eq [key]
      maildir.list("tmp").should be_empty
    end

    it "works on a message still in new" do
      maildir = temp_maildir
      message = maildir.add("first")
      message.rewrite("second")
      message.dir.should eq "new"
      message.data.should eq "second"
    end

    it "raises when the message is in tmp or gone" do
      maildir = temp_maildir
      expect_raises(Exception, /Can only rewrite/) { Maildir::Message.new(maildir).rewrite("x") }

      message = maildir.add("body")
      message.destroy
      expect_raises(File::NotFoundError) { message.rewrite("x") }
      maildir.list("tmp").should be_empty
    end
  end

  describe "#move_to" do
    it "moves the file into another maildir, keeping dir, unique name and info" do
      maildir = temp_maildir
      folder = maildir.folder("a")
      message = maildir.add("body")
      message.process
      key = message.key

      message.move_to(folder).should eq key
      message.maildir.should eq folder
      message.key.should eq key
      message.data.should eq "body"
      maildir.list("cur").should be_empty
      folder.list("cur").map(&.key).should eq [key]
    end

    it "is a no-op when the target is the message's own maildir" do
      maildir = temp_maildir
      message = maildir.add("body")
      message.move_to(maildir).should eq message.key
      maildir.list("new").map(&.key).should eq [message.key]
    end

    it "raises when the message is in tmp or gone" do
      maildir = temp_maildir
      folder = maildir.folder("a")
      expect_raises(Exception, /Can only move/) { Maildir::Message.new(maildir).move_to(folder) }

      message = maildir.add("body")
      message.destroy
      expect_raises(File::NotFoundError) { message.move_to(folder) }
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
