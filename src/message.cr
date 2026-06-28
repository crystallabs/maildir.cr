class Maildir
  class Message
    # COLON seperates the unique name from the info
    COLON = ":"
    # The default info, to which flags are appended
    INFO = "2,"

    include Comparable(self)

    # Create a new message in maildir with data.
    # The message is first written to the tmp dir, then moved to new. This is
    # a shortcut for:
    #   message = Maildir::Message.new(maildir)
    #   message.write(data)
    def self.create(maildir, data)
      message = self.new(maildir)
      message.write(data)
      message
    end

    # DEPRECATED: Get the serializer.
    # @see Maildir.serializer
    def self.serializer
      Maildir.serializer
    end

    # DEPRECATED: Set the serializer.
    # @see Maildir.serializer=
    def self.serializer=(serializer)
      Maildir.serializer = serializer
    end

    getter :dir, :unique_name, :info

    @info : String | Nil
    @key : String | Nil
    @old_key : String | Nil
    @maildir : Maildir
    @dir : String | Nil
    @unique_name : String | Nil

    # Create a new, unwritten message or instantiate an existing message.
    # If key is nil, create a new message:
    #   Message.new(maildir) # => a new, unwritten message
    #
    # If +key+ is not nil, instantiate a message object for the message at
    # +key+.
    #   Message.new(maildir, key) # => an existing message
    def initialize(maildir, key = nil)
      @maildir = maildir
      if key.nil?
        @dir = "tmp"
        @info = nil
        @unique_name = Maildir::UniqueName.create
      else
        parse_key(key)
      end

      unless Maildir::SUBDIRS.includes? dir
        raise ArgumentError.new "State must be in #{Maildir::SUBDIRS.inspect}"
      end
    end

    # Compares messages by their paths. Returns 1, 0, or -1.
    def <=>(other : self)
      path <=> other.path
    end

    # Friendly inspect method
    def inspect
      "#<#{self.class} key=#{key} maildir=#{@maildir.inspect}>"
    end

    # Helper to get serializer.
    def serializer
      @maildir.serializer
    end

    # Writes data to disk. Can only be called on messages instantiated without
    # a key (which haven't been written to disk). After successfully writing
    # to disk, rename the message to the new dir
    #
    # Returns the message's key
    def write(data)
      raise "Can only write to messages in tmp" unless "tmp" == @dir

      # Write out contents to tmp
      serializer.dump(data, path)

      rename("new")
    end

    # Move a message from new to cur, add info.
    # Returns the message's key
    def process
      rename("cur", INFO)
    end

    # Set info on a message.
    # Returns the message's key if successful, false otherwise.
    def info=(info)
      raise "Can only set info on cur messages" unless "cur" == @dir
      rename("cur", info)
    end

    FLAG_NAMES = {
      passed:  "P",
      replied: "R",
      seen:    "S",
      trashed: "T",
      draft:   "D",
      flagged: "F",
    }

    def passed?
      flags.includes?("P")
    end

    def passed!
      add_flag("P")
    end

    def replied?
      flags.includes?("R")
    end

    def replied!
      add_flag("R")
    end

    def seen?
      flags.includes?("S")
    end

    def seen!
      add_flag("S")
    end

    def trashed?
      flags.includes?("T")
    end

    def trashed!
      add_flag("T")
    end

    def draft?
      flags.includes?("D")
    end

    def draft!
      add_flag("D")
    end

    def flagged?
      flags.includes?("F")
    end

    def flagged!
      add_flag("F")
    end

    # Returns an array of single letter flags applied to the message
    def flags
      @info.to_s.sub(INFO, "").chars.map(&.to_s)
    end

    # Sets the flags on a message.
    # Returns the message's key if successful, false otherwise.
    def flags=(flags)
      self.info = INFO + sort_flags(flags.to_a.flatten.join(""))
    end

    # Adds a flag to a message.
    # Returns the message's key if successful, false otherwise.
    def add_flag(flag)
      self.flags = (flags << flag.upcase)
    end

    # Removes flags from a message.
    # Returns the message's key if successful, false otherwise.
    #
    # flags:: String or Array
    def remove_flag(flags)
      return self.flags if flags.blank?
      self.flags = self.flags.reject { |flag| flag =~ /[#{flags}]/i }
    end

    # Returns the filename of the message
    def filename
      [unique_name, info].compact.join(COLON)
    end

    # Returns the key to identify the message
    def key
      File.join(dir.to_s, filename)
    end

    # Returns the full path to the message
    def path
      File.join(@maildir.path, key)
    end

    # Returns the message's data from disk.
    # If the path doesn't exist, raises File::NotFoundError.
    def data
      guard(true) { serializer.load(path) }
    end

    # Updates the modification and access time. Returns nil if successful, false
    # if the file doesn't exist.
    def utime(atime, mtime)
      guard { File.utime(atime, mtime, path) }
    end

    # Returns the message's mtime, or false if the file doesn't exist.
    def mtime
      guard { File.info(path).modification_time }
    end

    # Deletes the message path.
    # Returns nil if the file was destroyed, false if the file was missing.
    def destroy
      guard { File.delete(path) }
    end

    # Guard access to the file system by rescuing File::NotFoundError, which
    # happens if the file is missing. When the block fails and +reraise+ is
    # false, returns false, otherwise reraises the original error.
    protected def guard(reraise = false, &)
      yield
    rescue e : File::NotFoundError
      if ok = @old_key
        # Restore ourselves to the old state
        parse_key(ok)
      end

      reraise ? raise(e) : false
    end

    # Sets dir, unique_name, and info based on the key
    protected def parse_key(key)
      @dir, filename = key.split(File::SEPARATOR)
      @unique_name, sep, info = filename.partition(COLON)
      # A missing info part (new/tmp messages) must stay nil, otherwise #filename
      # would re-append a stray trailing colon and no longer match the real file.
      @info = sep.empty? ? nil : info
    end

    # Ensure the flags are uppercase and sorted
    protected def sort_flags(flags)
      flags.split("").map(&.upcase).sort!.uniq.join("")
    end

    protected def old_path
      File.join(@maildir.path, @old_key || "")
    end

    # Renames the message. Returns the new key if successful, false otherwise.
    protected def rename(new_dir, new_info = nil)
      # Save the old key so we can revert to the old state
      @old_key = key

      # Set the new state
      @dir = new_dir
      @info = new_info if new_info

      guard do
        File.rename(old_path, path) unless old_path == path
        @old_key = nil # So guard() doesn't reset to a bad state
        return key
      end
    end
  end
end
