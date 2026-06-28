require "./spec_helper"

describe Maildir::UniqueName do
  it "generates unique names" do
    names = Array.new(1000) { Maildir::UniqueName.create }
    names.uniq.size.should eq names.size
  end

  it "embeds the process id and an incrementing counter" do
    name = Maildir::UniqueName.create
    name.should match /P#{Process.pid}Q\d+/
  end

  it "increments the per-process counter monotonically" do
    a = Maildir::UniqueName.counter
    b = Maildir::UniqueName.counter
    b.should be > a
  end

  it "uses the hostname as the right-hand part" do
    Maildir::UniqueName.create.split(".").last.should eq System.hostname.split(".").last
  end
end
