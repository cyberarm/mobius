module Kernel
  def log(*args)
    msg = case args.size
          when 1
            "[LOG] #{args[0]}"
          when 2
            "[#{args[0]}] #{args[1]}"
          else
            raise ArgumentError
          end

    puts "[#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}] #{msg}"
  end
end
