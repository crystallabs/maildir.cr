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

  it "renders the same value through to_s and string interpolation" do
    name = Maildir::UniqueName.new
    "#{name}".should eq name.to_s
  end

  it "uses a fixed-width microsecond within the current second" do
    name = Maildir::UniqueName.create
    micro = name.split(".")[1].lchop('M').partition("P").first
    micro.size.should eq 6
    micro.to_i.should be < 1_000_000
  end

  it "sorts chronologically as a plain string" do
    # Zero padding is what makes the seconds/microseconds prefix sort as a
    # string the same way it sorts as a point in time.
    prefixes = Array.new(200) { Maildir::UniqueName.create.partition("P").first }
    prefixes.should eq prefixes.sort
  end
end
