require "mutex" # For mutex support
require "socket" # For getting the hostname

# Class for generating unique file names for new messages
class Maildir
  class UniqueName
    COUNTER_MUTEX = Mutex.new

    @@counter = 0

    # Return a thread-safe increasing counter
    def self.counter
      COUNTER_MUTEX.synchronize do
        @@counter = @@counter.to_i.succ
      end
    end

    def self.create
      self.new.to_s
    end

    # Return a unique file name based on strategy
    def initialize
      # Use the same time object
      @now = Time.utc
    end

    # Return the name as a string
    def to_s
      [left, middle, right].join(".")
    end

    # The left part of the unique name is the number of seconds from since the
    # UNIX epoch
    protected def left
      @now.to_unix.to_s
    end

    # The middle part contains the microsecond, the process id, and a
    # per-process incrementing counter
    protected def middle
      "M"+ microsecond.to_s+ "P#{process_id}Q#{delivery_count}"
    end

    # The right part is the hostname
    protected def right
      #Socket.gethostname
      System.hostname
    end

    protected def microsecond
      # Crystal will have TicksPerMicrosecond after https://github.com/crystal-lang/crystal/pull/4707
      # Until that's included and #microsecond is added, here's our custom implementation:
      @now.to_unix_ms.to_s
    end

    protected def process_id
      Process.pid.to_s
    end

    protected def delivery_count
      self.class.counter.to_s
    end
  end
end
