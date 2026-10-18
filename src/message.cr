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
      message = new(maildir)
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

    # Splits a key into its dir, unique name, and info parts.
    # Raises ArgumentError if the key is not of the form "dir/unique_name[:info]".
    def self.parse_key(key : String) : {String, String, String?}
      dir, separator, filename = key.partition(File::SEPARATOR)
      if separator.empty? || dir.empty? || filename.empty? || filename.includes?(File::SEPARATOR)
        raise ArgumentError.new "Key must be of the form \"dir#{File::SEPARATOR}filename\", got #{key.inspect}"
      end

      unique_name, separator, info = filename.partition(COLON)
      # A missing info part (new/tmp messages) must stay nil, otherwise #filename
      # would re-append a stray trailing colon and no longer match the real file.
      {dir, unique_name, separator.empty? ? nil : info}
    end

    getter dir : String
    getter unique_name : String
    getter info : String?

    @old_key : String?
    # The maildir this message lives in.
    getter maildir : Maildir

    # Create a new, unwritten message or instantiate an existing message.
    # If key is nil, create a new message:
    #   Message.new(maildir) # => a new, unwritten message
    #
    # If +key+ is not nil, instantiate a message object for the message at
    # +key+.
    #   Message.new(maildir, key) # => an existing message
    def initialize(@maildir : Maildir, key : String? = nil)
      if key.nil?
        @dir = "tmp"
        @info = nil
        @unique_name = Maildir::UniqueName.create
      else
        @dir, @unique_name, @info = Message.parse_key(key)
      end

      unless Maildir::SUBDIRS.includes? dir
        raise ArgumentError.new "State must be in #{Maildir::SUBDIRS.inspect}"
      end
    end

    # Compares messages by their paths. Returns 1, 0, or -1.
    def <=>(other : self)
      path <=> other.path
    end

    def hash(hasher)
      path.hash(hasher)
    end

    # Friendly inspect method
    def inspect(io : IO) : Nil
      io << "#<" << self.class << " key=" << key << " maildir="
      @maildir.inspect(io)
      io << '>'
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

    # Moves a message from new to cur, adding the default info. A message which
    # is already in cur is left alone, flags included, so calling this twice is
    # harmless. Raises on a message in tmp, which has to be written first.
    # Returns the message's key.
    def process
      raise "Can only process messages in new" if "tmp" == @dir
      return key if "cur" == @dir
      rename("cur", INFO)
    end

    # Set info on a message.
    # Returns the message's key if successful, false otherwise.
    def info=(info)
      raise "Can only set info on cur messages" unless "cur" == @dir
      rename("cur", info)
    end

    # Replaces the message's contents on disk, atomically: the new data is
    # written to a file of the same unique name in "tmp", flushed if
    # `Maildir.fsync?` says so, and renamed over the existing file. A concurrent
    # reader therefore sees either the old or the new message, never a partial
    # one. Can only be called on messages in "new" or "cur"; raises
    # File::NotFoundError if the message is gone.
    #
    # Returns the message's key.
    def rewrite(data)
      raise "Can only rewrite messages in new or cur" if "tmp" == @dir
      raise File::NotFoundError.new("Message is gone", file: path) unless File.exists?(path)

      tmp_path = File.join(@maildir.tmp_path, @unique_name)
      serializer.dump(data, tmp_path)
      File.rename(tmp_path, path)
      key
    end

    # Moves the message into another maildir, typically a folder of the same
    # root, keeping its dir, unique name and info. Can only be called on
    # messages in "new" or "cur"; raises File::NotFoundError if the message is
    # gone. Afterwards the message belongs to the target maildir.
    #
    # Returns the message's key.
    def move_to(target : Maildir)
      raise "Can only move messages in new or cur" if "tmp" == @dir
      return key if target.path == @maildir.path

      File.rename(path, File.join(target.path, key))
      @maildir = target
      key
    end

    # The standard maildir flags, and the letters representing them.
    FLAG_NAMES = {
      passed:  "P",
      replied: "R",
      seen:    "S",
      trashed: "T",
      draft:   "D",
      flagged: "F",
    }

    {% for name, flag in FLAG_NAMES %}
      # Returns true if the message carries the "{{ flag.id }}" ({{ name.id }}) flag.
      def {{ name.id }}?
        flags.includes?({{ flag }})
      end

      # Adds the "{{ flag.id }}" ({{ name.id }}) flag to the message.
      # Returns the message's key if successful, false otherwise.
      def {{ name.id }}!
        add_flag({{ flag }})
      end
    {% end %}

    # Returns an array of single letter flags applied to the message
    def flags : Array(String)
      info = @info
      return [] of String unless info
      info.lchop(INFO).chars.map(&.to_s)
    end

    # Sets the flags on a message.
    # Returns the message's key if successful, false otherwise.
    #
    # flags:: String or Enumerable of flags
    def flags=(flags)
      self.info = INFO + normalize_flags(flags)
    end

    # Adds one or more flags to a message.
    # Returns the message's key if successful, false otherwise.
    #
    # flag:: String or Enumerable of flags
    def add_flag(flag)
      self.flags = flags.join + normalize_flags(flag)
    end

    # Removes flags from a message.
    # Returns the message's key if successful, false otherwise.
    #
    # flags:: String or Enumerable of flags
    def remove_flag(flags)
      removed = normalize_flags(flags)
      return key if removed.empty?
      self.flags = self.flags.reject { |flag| removed.includes?(flag.upcase) }
    end

    # Returns the filename of the message
    def filename
      if info = @info
        "#{@unique_name}#{COLON}#{info}"
      else
        @unique_name
      end
    end

    # Returns the key to identify the message
    def key
      File.join(dir, filename)
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
        @dir, @unique_name, @info = Message.parse_key(ok)
      end

      reraise ? raise(e) : false
    end

    # Returns the given flags (a String or an Enumerable of flags) as a single
    # uppercase, sorted, duplicate-free String.
    protected def normalize_flags(flags) : String
      chars = flags.is_a?(String) ? flags.chars : flags.flat_map(&.to_s.chars)
      chars.map!(&.upcase).sort!.uniq!.join
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
