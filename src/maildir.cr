require "file_utils" # For mkdir_p

require "./**"

class Maildir
  SUBDIRS = {"tmp", "new", "cur"}

  # Maildir++ folders live in the root maildir as sibling directories whose
  # name is the folder name prefixed with a dot; nesting is expressed by
  # joining the name components with a dot too (".Parent.Child"). Every folder
  # also carries an empty "maildirfolder" file, so that other tools recognize
  # it as a folder rather than as a maildir in its own right.
  FOLDER_PREFIX    = "."
  FOLDER_SEPARATOR = "."
  FOLDER_MARKER    = "maildirfolder"

  include Comparable(self)

  getter path : String
  setter serializer : Maildir::Serializer::Base?

  @serializer : Maildir::Serializer::Base?
  @folder : Bool?

  # Default serializer.
  DEFAULT_SERIALIZER = Maildir::Serializer::Base.new
  @@serializer : Maildir::Serializer::Base = DEFAULT_SERIALIZER

  # Gets the default serializer.
  def self.serializer : Maildir::Serializer::Base
    @@serializer
  end

  # Sets the default serializer.
  def self.serializer=(serializer : Maildir::Serializer::Base)
    @@serializer = serializer
  end

  # Whether messages are flushed to disk before being moved from "tmp" into
  # "new". On by default: the maildir format promises that a message which is
  # visible in "new" is complete, and only an fsync can make that hold across a
  # crash or a power loss.
  @@fsync = true

  # Returns true if messages are fsynced before delivery.
  def self.fsync? : Bool
    @@fsync
  end

  # Sets whether messages are fsynced before delivery. Turning this off trades
  # the crash-safety guarantee above for throughput, which can be worth it on
  # rotational or network storage when the data is reproducible anyway.
  def self.fsync=(fsync : Bool)
    @@fsync = fsync
  end

  # Create a new maildir at +path+. If +create+ is true, will ensure that the
  # required subdirectories exist.
  def initialize(path, create = true)
    # Absolute path, with a trailing separator
    @path = File.join(File.expand_path(path), "")
    create_directories if create
  end

  # Returns own serializer or falls back to the default one. Deliberately does
  # not memoize, so that a later change of `Maildir.serializer` is picked up by
  # maildirs which don't have a serializer of their own.
  def serializer : Maildir::Serializer::Base
    @serializer || @@serializer
  end

  # Compare maildirs by their paths. Returns 1, 0, or -1.
  def <=>(other : self)
    path <=> other.path
  end

  def hash(hasher)
    path.hash(hasher)
  end

  # Friendly inspect method
  def inspect(io : IO) : Nil
    io << "#<" << self.class << " path=" << @path << '>'
  end

  # define methods tmp_path, new_path, & cur_path
  def tmp_path
    File.join(@path, "tmp")
  end

  def cur_path
    File.join(@path, "cur")
  end

  def new_path
    File.join(@path, "new")
  end

  # Ensure subdirectories exist. This can safely be called multiple times and
  # from several processes at once, but must hit the disk. Avoid calling this
  # if you're certain the directories exist.
  def create_directories
    SUBDIRS.each do |subdir|
      mkdir_p File.join(path, subdir)
    end

    if folder?
      marker = File.join(path, FOLDER_MARKER)
      File.touch(marker) unless File.exists?(marker)
    end
  end

  # "mkdir -p" which tolerates other processes creating the same directories at
  # the same moment. FileUtils.mkdir_p looks before it creates, so it raises
  # File::AlreadyExistsError when it loses that race - which, for a format
  # whose whole point is that several processes share a maildir without locks,
  # is a routine event rather than an error. Creating one component at a time
  # and accepting an already-created one keeps that from aborting a delivery.
  private def mkdir_p(dir : String) : Nil
    return if Dir.exists?(dir)

    parent = File.dirname(dir)
    mkdir_p(parent) unless parent == dir

    begin
      Dir.mkdir(dir)
    rescue e : File::AlreadyExistsError
      # Somebody else got there first, which is exactly what we wanted, as long
      # as what they created is a directory
      raise e unless Dir.exists?(dir)
    end
  end

  # Returns true if +path+ holds a maildir, i.e. has the tmp, new and cur
  # subdirectories.
  def self.maildir?(path) : Bool
    SUBDIRS.all? { |subdir| Dir.exists?(File.join(path, subdir)) }
  end

  # Returns true if this maildir is a Maildir++ folder of another maildir: its
  # directory name is dot-prefixed *and* it sits inside a maildir. The second
  # condition is what keeps a root maildir which merely lives at a dot-path
  # (say "~/.maildir") from being taken for a folder of its parent directory.
  #
  # The answer is settled once, on first use, so a maildir doesn't change its
  # mind halfway through if the surrounding directories change.
  def folder? : Bool
    folder = @folder
    return folder unless folder.nil?

    @folder = File.basename(bare_path).starts_with?(FOLDER_PREFIX) &&
              Maildir.maildir?(File.dirname(bare_path))
  end

  # The Maildir++ name of this folder ("a", "a.x"), or nil for a root maildir.
  def folder_name : String?
    return unless folder?
    File.basename(bare_path).lchop(FOLDER_PREFIX)
  end

  # The root maildir this folder belongs to. Returns self if this maildir is
  # already a root.
  def root : Maildir
    folder? ? Maildir.new(File.dirname(bare_path), false) : self
  end

  # The maildir this folder is nested in, or nil for a root maildir.
  def parent : Maildir?
    return unless name = folder_name
    if separator = name.rindex(FOLDER_SEPARATOR)
      Maildir.new(File.join(root.path, FOLDER_PREFIX + name[0, separator]), false)
    else
      root
    end
  end

  # Returns the maildir for the named subfolder of this one, creating the
  # directories of the whole chain unless +create+ is false. Names nest with a
  # dot, so these two are the same folder:
  #   maildir.folder("a.x")
  #   maildir.folder("a").folder("x")
  def folder(name : String, create = true) : Maildir
    components = name.split(FOLDER_SEPARATOR)
    if name.empty? || name.includes?(File::SEPARATOR) || components.any?(&.empty?)
      raise ArgumentError.new "Invalid folder name: #{name.inspect}"
    end

    components.reduce(self) { |maildir, component| maildir.child_folder(component, create) }
  end

  # Returns this maildir's immediate subfolders, sorted by path. Deeper
  # descendants are reached by asking those folders in turn. Only directories
  # which actually hold a maildir count; a stray dot-directory in the root
  # (say ".git") is not a folder.
  def folders : Array(Maildir)
    root_path = root.path
    prefix = folder_name.try { |own_name| "#{own_name}#{FOLDER_SEPARATOR}" } || ""

    maildirs = [] of Maildir
    return maildirs unless Dir.exists?(root_path)

    Dir.each_child(root_path) do |entry|
      next unless entry.starts_with?(FOLDER_PREFIX)
      name = entry.lchop(FOLDER_PREFIX)
      next unless name.starts_with?(prefix)

      # Only immediate children: anything below them still carries a separator
      rest = name.lchop(prefix)
      next if rest.empty? || rest.includes?(FOLDER_SEPARATOR)

      folder_path = File.join(root_path, entry)
      next unless Maildir.maildir?(folder_path)

      maildirs << Maildir.new(folder_path, false)
    end

    maildirs.sort!
  end

  # Returns the maildir for an immediate subfolder of this one.
  protected def child_folder(name : String, create) : Maildir
    full_name = (own_name = folder_name) ? "#{own_name}#{FOLDER_SEPARATOR}#{name}" : name
    Maildir.new(File.join(root.path, FOLDER_PREFIX + full_name), create)
  end

  # The path without its trailing separator
  private def bare_path
    @path.rchop(File::SEPARATOR)
  end

  # Returns an array of messages from the "new" or "cur" directory, sorted by
  # key. If options[:flags] is specified and dir is "cur", returns only the
  # messages carrying exactly those flags.
  #
  # E.g.
  # maildir.list("cur", {:flags => "F"}) # => lists all messages with flag "F"
  # maildir.list("cur", {:flags => "FS"}) # => lists all messages with flags "F" and "S"; flags must be specified in ascending ASCII order ("FS" and not "SF")
  # maildir.list("cur", {:flags => ""}) # => lists all messages without any flags
  # This option does not work for the "new" directory
  #
  # If options[:limit] is specified, returns only so many keys.
  #
  # E.g.
  #  maildir.list("new") # => all new messages
  #  maildir.list("cur", {:limit => 10}) # => 10 oldest messages in cur
  def list(dir : String, options = {} of Symbol => String | Int32?)
    unless SUBDIRS.includes? dir
      raise ArgumentError.new "dir must be one of #{SUBDIRS.inspect}"
    end

    # Set flags to filter messages
    # Silently ignored unless dir is "cur"
    flags = dir == "cur" ? options[:flags]?.try(&.to_s) : nil
    keys = get_dir_listing(dir, flags)

    # Sort the keys (chronological order)
    # TODO: make sorting configurable
    keys.sort!

    # Apply the limit after sorting
    limit = options[:limit]?
    keys = keys[0, limit] if limit.is_a?(Int) && limit < keys.size

    # Map keys to message objects
    keys.map { |key| get(key) }
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
  def get_stale_tmp(time : Time = Time.utc - 36.hours)
    list("tmp").select do |message|
      mtime = message.mtime
      mtime.is_a?(Time) && mtime < time
    end
  end

  # Returns an array of keys in dir. If +flags+ is not nil, only messages whose
  # info part is exactly ":2,<flags>" are returned.
  protected def get_dir_listing(dir : String, flags : String? = nil)
    keys = [] of String
    dir_path = File.join(path, dir)
    return keys unless Dir.exists?(dir_path)

    suffix = flags ? "#{Maildir::Message::COLON}#{Maildir::Message::INFO}#{flags}" : nil

    Dir.each_child(dir_path) do |name|
      next if name.starts_with?('.') # Skip dotfiles, as Dir.glob("*") would
      next if suffix && !name.ends_with?(suffix)
      keys << File.join(dir, name)
    end

    keys
  end
end
