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
