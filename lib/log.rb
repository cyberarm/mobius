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

    if defined?(Mobius::ModerationServerClient) && Mobius::ModerationServerClient.running?
      Mobius::ModerationServerClient.post(
        JSON.dump(
          {
            type: :log,
            message: msg
          }
        )
      )
    end

    puts "[#{Time.now.strftime("%Y-%m-%d %H:%M:%S")}] #{msg}"
  end
end

module Mobius
  LOG_CODE = {
    kicklog:  1,
    banlog:   2,
    unbanlog: 3,
    warnlog:  4,
    stafflog: 5,
    mutelog: 6,
  }.freeze

  MODERATOR_ACION = {
    ban: 0,
    kick: 1,
    warning: 2,
  }.freeze
end
