require "./spec_helper"

it "works!" do
  maildir= temp_maildir
  message= maildir.add("Hello, Crystal!")

  maildir.list( "new").size.should eq 1

  message.process

  maildir.list( "new").size.should eq 0
  maildir.list( "cur").size.should eq 1

  message.add_flag("S") # Mark the message as "seen"
  message.add_flag("F") # Mark the message as "flagged"
  message.remove_flag("F") # unflag the message
  message.add_flag("DPR") # Mark the message as "draft", "passed" and "replied"
  message.remove_flag("DPR") # Remove the three flags
  message.add_flag("T") # Mark the message as "trashed"
  message.add_flag("X") # Add arbitrary-letter flag

  maildir.list("cur",  {:flags => "F"}).size.should eq 0
  maildir.list("cur",  {:flags => "FS"}).size.should eq 0
  maildir.list("cur",  {:flags => ""}).size.should eq 0
  maildir.list("cur",  {:flags => "STX"}).size.should eq 1

  key= message.key
  data= message.data

  message_copy = maildir.get(key)
  message.should eq message_copy

  message.destroy # => returns the frozen message
  maildir.list("cur").size.should eq 0

  maildir.get_stale_tmp.size.should eq 0

  my_data = "plain string data"
  message = maildir.add(my_data)
  message.data.should eq my_data

  maildir.serializer= Maildir::Serializer::JSON.new
  my_data = {"foo" => nil, "my_array" => [1,2,3]}
  message = maildir.add(my_data) # writes {"foo":null,"my_array":[1,2,3]}
  message.data.should eq my_data

  #maildir.serializer= Maildir::Serializer::YAML.new
  #my_data = {"foo" => nil, "my_array" => [1,2,3]}
  #message = maildir.add(my_data)
  #puts my_data.inspect
  #puts message.data.inspect
  #puts message.data == my_data # => true
end
