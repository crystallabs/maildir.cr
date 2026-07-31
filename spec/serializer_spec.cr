require "./spec_helper"

describe Maildir::Serializer do
  describe Maildir::Serializer::Base do
    it "round-trips a plain string" do
      maildir = temp_maildir
      maildir.serializer = Maildir::Serializer::Base.new
      data = "plain string data"
      message = maildir.add(data)
      message.data.should eq data
    end

    it "returns the number of bytes written from dump" do
      maildir = temp_maildir
      serializer = Maildir::Serializer::Base.new
      path = File.join(maildir.tmp_path, "dump_test")
      serializer.dump("čćž", path).should eq 6 # 3 two-byte characters
    end
  end

  describe "fsync" do
    it "is enabled by default" do
      Maildir.fsync?.should be_true
    end

    it "flushes every message to disk before it is moved into new" do
      maildir = temp_maildir
      serializer = CountingSerializer.new
      maildir.serializer = serializer

      maildir.add("body")
      maildir.add("body")
      serializer.syncs.should eq 2
    end

    it "can be turned off, and still writes the data" do
      maildir = temp_maildir
      serializer = CountingSerializer.new
      maildir.serializer = serializer

      Maildir.fsync = false
      begin
        message = maildir.add("body")
      ensure
        Maildir.fsync = true
      end

      serializer.syncs.should eq 0
      message.data.should eq "body"
    end
  end

  describe Maildir::Serializer::JSON do
    it "round-trips structured data as JSON" do
      maildir = temp_maildir
      maildir.serializer = Maildir::Serializer::JSON.new
      data = {"foo" => nil, "my_array" => [1, 2, 3]}
      message = maildir.add(data)
      message.data.should eq data
    end
  end

  describe Maildir::Serializer::YAML do
    it "round-trips structured data as YAML" do
      maildir = temp_maildir
      maildir.serializer = Maildir::Serializer::YAML.new
      data = {"foo" => nil, "my_array" => [1, 2, 3]}
      message = maildir.add(data)
      message.data.should eq data
    end
  end
end
