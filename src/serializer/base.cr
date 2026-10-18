class Maildir
  module Serializer
    # The Maildir::Serializer::Base class reads & writes data to disk as a
    # string. Other serializers (e.g. Maildir::Serializer::Mail) can extend this
    # class to do some pre- and post-processing of the string.
    #
    # The Serializer API has two methods:
    #   load(path) # => returns data
    #   dump(data, path) # => returns number of bytes written
    class Base
      # Reads the file at path. Returns the contents of path.
      def load(path)
        File.read path
      end

      # Writes data to the file at path. Returns the number of bytes written.
      def dump(data, path)
        slice = data.to_s.to_slice
        File.open(path, "w") do |file|
          file.write(slice)
          sync(file) if Maildir.fsync?
        end
        slice.size
      end

      # Flushes the message to disk. Called while the message is still in "tmp",
      # so that moving it into "new" can't expose a truncated message after a
      # crash. Serializers that manage their own durability can override this.
      protected def sync(file : File) : Nil
        file.fsync
      end
    end
  end
end
