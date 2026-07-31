# Class for generating unique file names for new messages
class Maildir
  class UniqueName
    COUNTER_MUTEX = Mutex.new

    @@counter = 0
    @@hostname : String?

    @now : Time
    @count : Int32

    # Return a thread-safe increasing counter
    def self.counter
      COUNTER_MUTEX.synchronize do
        @@counter += 1
      end
    end

    # The hostname, with the characters that are not allowed in a maildir
    # filename escaped as the maildir spec prescribes. Looked up only once, as
    # it can't meaningfully change during the lifetime of a process.
    def self.hostname : String
      @@hostname ||= System.hostname.gsub('/', "\\057").gsub(':', "\\072")
    end

    def self.create
      self.new.to_s
    end

    # Return a unique file name based on strategy
    def initialize
      # Take the time and the counter once, so that the name of a given
      # instance is stable no matter how often it is rendered
      @now = Time.utc
      @count = self.class.counter
    end

    # Return the name as a string
    def to_s(io : IO) : Nil
      io << left << '.' << middle << '.' << right
    end

    # The left part of the unique name is the number of seconds from since the
    # UNIX epoch
    protected def left
      @now.to_unix.to_s
    end

    # The middle part contains the microsecond, the process id, and a
    # per-process incrementing counter
    protected def middle
      "M#{microsecond}P#{process_id}Q#{delivery_count}"
    end

    # The right part is the hostname
    protected def right
      self.class.hostname
    end

    # The microseconds elapsed within the current second. Zero-padded to a
    # fixed width so that names created within the same second still sort
    # chronologically as plain strings.
    protected def microsecond
      (@now.nanosecond // 1_000).to_s.rjust(6, '0')
    end

    protected def process_id
      Process.pid.to_s
    end

    protected def delivery_count
      @count.to_s
    end
  end
end
