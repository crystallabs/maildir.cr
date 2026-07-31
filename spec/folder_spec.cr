require "./spec_helper"

# Creates the Maildir++ tree used throughout these specs:
# | maildir
# |-- a
# |   |-- x
# |   |-- y
# |-- b
def maildir_with_folders
  maildir = temp_maildir
  %w[a b a.x a.y].each { |name| maildir.folder(name) }
  maildir
end

describe "Maildir folders" do
  describe ".maildir?" do
    it "recognizes a directory holding the three subdirectories" do
      maildir = temp_maildir
      Maildir.maildir?(maildir.path).should be_true
      Maildir.maildir?(File.dirname(maildir.path.rchop('/'))).should be_false
      Maildir.maildir?(File.join(maildir.path, "nonexistent")).should be_false
    end
  end

  describe "#folder?, #folder_name and #root" do
    it "distinguishes a root maildir from a folder" do
      maildir = temp_maildir
      maildir.folder?.should be_false
      maildir.folder_name.should be_nil
      maildir.root.should eq maildir

      folder = maildir.folder("a")
      folder.folder?.should be_true
      folder.folder_name.should eq "a"
      folder.root.should eq maildir
    end

    it "treats a maildir which merely lives at a dot-path as a root" do
      base = File.join(Dir.tempdir, "maildir_dotroot_#{Process.pid}")
      FileUtils.rm_rf(base)
      TEMP_MAILDIRS << base
      maildir = Maildir.new(File.join(base, ".maildir"))

      maildir.folder?.should be_false
      maildir.folder_name.should be_nil
      maildir.root.should eq maildir
      maildir.parent.should be_nil
      File.exists?(File.join(maildir.path, Maildir::FOLDER_MARKER)).should be_false
    end

    it "reports the full dotted name of a nested folder" do
      maildir = maildir_with_folders
      nested = maildir.folder("a").folder("x")
      nested.folder_name.should eq "a.x"
      nested.root.should eq maildir
    end
  end

  describe "#folder" do
    it "creates the folder as a dot-prefixed directory in the root maildir" do
      maildir = temp_maildir
      folder = maildir.folder("a")

      folder.path.should eq File.join(maildir.path, ".a", "")
      Maildir::SUBDIRS.each do |subdir|
        Dir.exists?(File.join(folder.path, subdir)).should be_true
      end
    end

    it "nests by dot and by chaining interchangeably" do
      maildir = temp_maildir
      maildir.folder("a.x").should eq maildir.folder("a").folder("x")
    end

    it "creates the intermediate folders of a dotted name" do
      maildir = temp_maildir
      maildir.folder("a.x")
      Dir.exists?(File.join(maildir.path, ".a", "cur")).should be_true
    end

    it "keeps nested folders flat in the root, not inside their parent" do
      maildir = temp_maildir
      nested = maildir.folder("a").folder("x")

      nested.path.should eq File.join(maildir.path, ".a.x", "")
      Dir.exists?(File.join(maildir.path, ".a", ".x")).should be_false
    end

    it "does not touch the disk when create is false" do
      maildir = temp_maildir
      folder = maildir.folder("a", false)
      Dir.exists?(folder.path).should be_false
    end

    it "rejects names that would escape or confuse the layout" do
      maildir = temp_maildir
      ["", ".", ".a", "a.", "a..x", "a/x", "../x"].each do |name|
        expect_raises(ArgumentError, /Invalid folder name/) { maildir.folder(name) }
      end
    end

    it "writes a maildirfolder marker into folders but not into the root" do
      maildir = temp_maildir
      folder = maildir.folder("a")

      File.exists?(File.join(folder.path, Maildir::FOLDER_MARKER)).should be_true
      File.exists?(File.join(maildir.path, Maildir::FOLDER_MARKER)).should be_false
    end

    it "is idempotent and does not refresh the marker on every call" do
      maildir = temp_maildir
      marker = File.join(maildir.folder("a").path, Maildir::FOLDER_MARKER)
      mtime = File.info(marker).modification_time

      maildir.folder("a")
      File.info(marker).modification_time.should eq mtime
    end
  end

  describe "#folders" do
    it "lists only the immediate subfolders, sorted" do
      maildir = maildir_with_folders
      maildir.folders.map(&.folder_name).should eq ["a", "b"]
      maildir.folder("a").folders.map(&.folder_name).should eq ["a.x", "a.y"]
      maildir.folder("a.x").folders.should be_empty
    end

    it "is empty for a maildir without folders" do
      temp_maildir.folders.should be_empty
    end

    it "ignores dot files and non-maildir entries in the root" do
      maildir = maildir_with_folders
      File.write(File.join(maildir.path, ".subscriptions"), "a\n")
      maildir.folders.map(&.folder_name).should eq ["a", "b"]
    end
  end

  describe "#parent" do
    it "walks back up the tree" do
      maildir = maildir_with_folders
      nested = maildir.folder("a.x")

      nested.parent.should eq maildir.folder("a")
      maildir.folder("a").parent.should eq maildir
      maildir.parent.should be_nil
    end
  end

  describe "messages" do
    it "keeps the messages of each folder separate from the root's" do
      maildir = maildir_with_folders
      folder = maildir.folder("a")
      nested = maildir.folder("a.x")

      maildir.add("root message")
      folder.add("folder message")
      nested.add("nested message")

      maildir.list("new").map(&.data).should eq ["root message"]
      folder.list("new").map(&.data).should eq ["folder message"]
      nested.list("new").map(&.data).should eq ["nested message"]
    end

    it "supports the full message lifecycle inside a folder" do
      folder = temp_maildir.folder("a")
      message = folder.add("body")
      message.process
      message.seen!

      folder.list("cur", {:flags => "S"}).map(&.key).should eq [message.key]
    end
  end
end
