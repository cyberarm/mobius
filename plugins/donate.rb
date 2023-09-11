mobius_plugin(name: "Donate", database_name: "donate", version: "0.0.1") do
  def donations_available?(player)
    donate_limit = MapSettings.get_map_setting(:donatelimit)
    map = ServerStatus.get(:current_map)
    map_elapsed_time = monotonic_time.to_i - ServerStatus.get(:map_start_time)

    if (donate_limit != 0 && map_elapsed_time < donate_limit * 60)
      remaining_seconds = (donate_limit * 60) - map_elapsed_time
      pp remaining_seconds, donate_limit * 60, map_elapsed_time

      page_player(player.name, "[MOBIUS] Donations are not allowed on #{map} in the first #{donate_limit} minutes. You have to wait #{remaining_seconds} more seconds.")

      return false
    end

    return true
  end

  def create_transaction(issuer, type, recipients = [], amount = nil)
    # Use RenRem.enqueue to ensure we only issue `pinfo` once per tick
    RenRem.enqueue("pinfo")

    @pending_transactions << {
      issuer: issuer,
      type: type,
      recipients: recipients,
      amount: amount,
      time: monotonic_time
    }
  end

  def donate(type, transaction)
    donator = PlayerData.player(transaction[:issuer])
    return unless donator

    max_amount = donator.money
    amount = transaction[:amount].is_a?(Numeric) ? transaction[:amount] : max_amount
    amount = max_amount if amount > max_amount

    if amount.positive?
      slice = (amount / transaction[:recipients].count.to_f).floor
      donation = @donations[donator.name] = {receivers: [], time: monotonic_time }

      transaction[:recipients].each do |recipient|
        mate = PlayerData.player(recipient)
        next unless mate

        RenRem.cmd("donate #{donator.id} #{mate.id} #{slice}")

        page_player(mate.name, "#{donator.name} has donated #{slice} credits to you.")
        donation[:receivers] << { name: mate.name, amount: slice, money: mate.money }

        mate.money += slice
      end

      # FIXME: Sometimes this message is not delivered!
      page_player(donator.name, "You have donated #{donation[:receivers].sum { |r| r[:amount]}} credits to #{type == :individual ? "#{transaction[:recipients][0]}" : "your team"}.")
    else
      page_player(donator.name, "Cannot donate nothing!")
      log "#{donator.name} attempted to donate #{amount.inspect} to #{type == :individual ? "#{transaction[:recipients][0]}" : "their team"}."
    end
  end

  def undonate(transaction)
    donator = PlayerData.player(transaction[:issuer])
    return unless donator

    donation = @donations[transaction[:issuer]]

    if donation
      taken_back = 0
      total_given = donation[:receivers].sum { |r| r[:amount] }

      donation[:receivers].each do |receiver|
        next unless receiver[:name]
        next unless receiver[:amount]
        next unless receiver[:money]

        player = PlayerData.player(receiver[:name])
        next unless player

        # Player has likely spent it, reject un-donate from them
        next if player.money <= receiver[:amount] + receiver[:money]

        RenRem.cmd("donate #{player.id} #{donator.id} #{receiver[:amount]}")
        taken_back += receiver[:amount]
        player.money -= receiver[:amount]

        page_player(player.name, "#{donator.name} has un-donated #{receiver[:amount]} credits from you.")
      end

      if taken_back == total_given
        page_player(donator.name, "You have un-undonated and received back #{taken_back} credits.")
      elsif taken_back == 0
        page_player(donator.name, "Unable to un-donated, all receivers have have spent credits since you donated to them.")
      else
        page_player(donator.name, "You have un-undonated and received back #{taken_back} of #{total_given} credits.")
      end

      @donations.delete(donator.name)
    else
      page_player(donator.name, "You have made no donations in the last #{@undonate_timeout} seconds or have already un-donated.")
    end
  end

  on(:start) do
    @donations = {}
    @pending_transactions = []
    @undonate_timeout = 5.0
  end

  on(:map_loaded) do
    @donations = {}
    @pending_transactions = []
  end

  on(:player_info_updated) do
    while(transaction = @pending_transactions.shift)
      case transaction[:type]
      when :individual
        donate(:individual, transaction)
      when :team
        donate(:team, transaction)
      when :undonate
        undonate(transaction)
      end
    end
  end

  on(:tick) do
    @donations.delete_if { |key, d| monotonic_time - d[:time] > @undonate_timeout }
  end

  command(:donate, aliases: [:d], arguments: 1..2, help: "!donate <nickname> [<amount>]") do |command|
    next unless donations_available?(command.issuer)

    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))
    amount = command.arguments.last

    unless player
      page_player(command.issuer.name, "Player not in game or name is not unique!")

      next
    end

    # Assume empty string means they intend to donate everything
    if amount.to_s.length.positive?
      begin
        amount = Integer(amount)
      rescue ArgumentError
        page_player(command.issuer.name, "Invalid amount: #{command.arguments.last}")

        next
      end
    end

    create_transaction(command.issuer.name, :individual, [player.name], amount) if player
  end

  command(:teamdonate, aliases: [:td], arguments: 0..1, help: "!teamdonate [<amount>]") do |command|
    next unless donations_available?(command.issuer)

    mates  = PlayerData.player_list.select { |ply| ply.ingame? && ply.team == command.issuer.team && ply != command.issuer }
    amount = command.arguments.first

    unless mates.count.positive?
      page_player(command.issuer.name, "You are the only one on your team!")

      next
    end

    # Assume empty string means they intend to donate everything
    if amount.to_s.length.positive?
      begin
        amount = Integer(amount)
      rescue ArgumentError
        page_player(command.issuer.name, "Invalid amount: #{command.arguments.first}")

        next
      end
    end

    create_transaction(command.issuer.name, :team, mates.map(&:name), amount) if mates.count.positive?
  end

  command(:undonate, aliases: [:ud], arguments: 0, help: "!undonate - Undo last donation (limited to 5 seconds)") do |command|
    donation = @donations[command.issuer.name]

    if donation
      create_transaction(command.issuer.name, :undonate)
    else
      page_player(command.issuer.name, "You have made no donations in the last #{@undonate_timeout} seconds or have already un-donated.")
    end
  end
end
