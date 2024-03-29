require "file_utils" # For mkdir_p

require "./**"

class Maildir

  SUBDIRS = {"tmp", "new", "cur"}

  include Comparable(self)

  getter :path
  setter :serializer

  @serializer : Maildir::Serializer::Base | Nil

  # Default serializer.
  DEFAULT_SERIALIZER = Maildir::Serializer::Base.new
  @@serializer = DEFAULT_SERIALIZER

  # Gets the default serializer.
  def self.serializer
    @@serializer
  end

  # Sets the default serializer.
  def self.serializer=(serializer)
    @@serializer = serializer
  end

  # Create a new maildir at +path+. If +create+ is true, will ensure that the
  # required subdirectories exist.
  def initialize(path, create = true)
    @path = File.expand_path(path)
    @path = File.join(@path, "/") # Ensure path has a trailing slash
    @path_regexp = Regex.new "^#{Regex.escape(@path)}" # For parsing directory listings
    create_directories if create
  end

  # Returns own serializer or falls back to default.
  def serializer
    @serializer ||= @@serializer
  end

  # Compare maildirs by their paths.
  # If maildir is a different class, return nil.
  # Otherwise, return 1, 0, or -1.
  def <=>(other)
    # Return nil if comparing different classes
    return nil unless self.class === other

    self.path <=> other.path
  end

  # Friendly inspect method
  def inspect
    "#<#{self.class} path=#{@path}>"
  end

  # define methods tmp_path, new_path, & cur_path
  def tmp_path() File.join(@path, "tmp") end
  def cur_path() File.join(@path, "cur") end
  def new_path() File.join(@path, "new") end

  # Ensure subdirectories exist. This can safely be called multiple times, but
  # must hit the disk. Avoid calling this if you're certain the directories
  # exist.
  def create_directories
    SUBDIRS.each do |subdir|
      subdir_path = File.join(path, subdir)
      FileUtils.mkdir_p(subdir_path)
    end
  end

  # Returns an arry of messages from :new or :cur directory, sorted by key.
  # If options[:flags] is specified and directory is :cur, returns messages with flags specified
  #
  # E.g.
  # maildir.list(:cur, :flags => 'F') # => lists all messages with flag 'F'
  # maildir.list(:cur, :flags => 'FS') # => lists all messages with flag 'F' and 'S'; Flags must be specified in acending ASCII order ('FS' and not 'SF')
  # maildir.list(:cur, :flags => '') # => lists all messages without any flags
  # This option does not work for :new directory
  #
  # If options[:limit] is specified, returns only so many keys.
  #
  # E.g.
  #  maildir.list(:new) # => all new messages
  #  maildir.list(:cur, :limit => 10) # => 10 oldest messages in cur
  def list(dir, options = {} of Symbol => String | Int32 | Nil)
    unless SUBDIRS.includes? dir
      raise ArgumentError.new "dir must be :new, :cur, or :tmp"
    end

    # Set flags to filter messages
    # Silently ignored if dir is :new
    flags = (dir== "cur") ? options[:flags]? : nil
    keys = get_dir_listing(dir, {flags: flags})

    # Sort the keys (chronological order)
    # TODO: make sorting configurable
    keys.sort!

    # Apply the limit after sorting
    if (limit = options[:limit]?) && (limit.is_a? Int) && (limit< keys.size)
      keys = keys[0,limit]
    end

    # Map keys to message objects
    keys.map{|key| get(key)}
  end

  # Writes data object out as a new message. Returns a Maildir::Message. See
  # Maildir::Message.create for more.
  def add(data)
    Maildir::Message.create(self, data)
  end

  # Returns a message object for key
  def get(key)
    Maildir::Message.new(self, key)
  end

  # Deletes the message for key by calling destroy() on the message.
  def delete(key)
    get(key).destroy
  end

  # Finds messages in the tmp folder that have not been modified since
  # +time+. +time+ defaults to 36 hours ago.
  def get_stale_tmp(time = Time.utc - 129_600.seconds)
    list("tmp").select do |message|
      (mtime = message.mtime) && mtime.is_a?(Time) && (mtime < time)
    end
  end

  # Returns an array of keys in dir
  protected def get_dir_listing(dir, options={} of Symbol => String | Nil)
  	filter = "*"
  	filter = "#{filter}:2,#{options[:flags]}" if options[:flags]?
    search_path = File.join(self.path, dir.to_s, filter)
    keys = Dir.glob(search_path)
    #  Remove the maildir's path from the keys
    keys.map! do |key|
      key.sub(@path_regexp, "")
    end
  end
end
