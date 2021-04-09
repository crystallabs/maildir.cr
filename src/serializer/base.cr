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

      # XXX
      def dump(data, path)
        # IO.copy_stream(data, path)
        # write(data.read, path)
        write(data, path)
      end

      protected def write(data, path)
        File.open path, "w", &.write(data.to_s.to_slice)
      end
    end
  end
end
