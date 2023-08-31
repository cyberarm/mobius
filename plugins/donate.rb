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

  def all_player_funds
    funds = {}

    RenRem.cmd_now("pinfo") do |response|
      lines = response.strip.lines

      lines[1..lines.count - 2].each do |line|
        split_data = line.split(",")

        name  = split_data[1]
        money = split_data[10].to_i

        funds[name] = money
      end

      # Fallback incase RenRem read failed
      PlayerData.player_list do |player|
        unless funds[player.name]
          log "Failed to retreive pinfo data for \"#{player.name}\" via RenRem, falling back to PlayerData."
          funds[player.name] = player.money
        end
      end
    end

    # id       = split_data[0].to_i
    # name     = split_data[1]
    # score    = split_data[2].to_i
    # team     = split_data[3].to_i
    # ping     = split_data[4].to_i
    # address  = split_data[5]
    # kbps     = split_data[6].to_i
    # rank     = split_data[7].to_i
    # kills    = split_data[8].to_i
    # deaths   = split_data[9].to_i
    # money    = split_data[10].to_i
    # kd       = split_data[11].to_f

    funds
  end

  on(:start) do
    @donations = {}
    @undonate_timeout = 5.0
  end

  on(:map_loaded) do
    @donations = {}
  end

  on(:tick) do
    @donations.delete_if { |key, d| monotonic_time - d[:time] > @undonate_timeout }
  end

  command(:donate, aliases: [:d], arguments: 1..2, help: "!donate <nickname> [<amount>]") do |command|
    player = PlayerData.player(PlayerData.name_to_id(command.arguments.first, exact_match: false))
    amount = command.arguments.last
    funds = all_player_funds
    max_amount = funds[command.issuer.name] || 0

    begin
      amount = Integer(amount)
    rescue ArgumentError
      amount = max_amount
    end

    amount = max_amount if amount > max_amount

    if player
      if amount.positive?
        if command.issuer.team == player.team && command.issuer.name != player.name
          if donations_available?(command.issuer)
            RenRem.cmd("donate #{command.issuer.id} #{player.id} #{amount}")
            RenRem.cmd("pinfo")

            page_player(command.issuer.name, "You have donated #{amount} credits to #{player.name}")
            page_player(player.name, "#{command.issuer.name} has donated #{amount} credits to you.")

            @donations[command.issuer.name] = {receivers: [{ name: player.name, amount: amount, money: funds[player.name] }], time: monotonic_time }
          end
        elsif command.issuer.name == player.name
          page_player(command.issuer.name, "You cannot donate to yourself.")
        else
          page_player(command.issuer.name, "Can only donate to players on your team.")
        end
      else
        page_player(command.issuer.name, "Cannot donate nothing!")
      end
    else
      page_player(command.issuer.name, "Player not in game or name is not unique!")
    end
  end

  # FIXME:
  command(:teamdonate, aliases: [:td], arguments: 0..1, help: "!teamdonate [<amount>]") do |command|
    mates  = PlayerData.player_list.select { |ply| ply.ingame? && ply.team == command.issuer.team && ply != command.issuer }
    amount = command.arguments.first
    funds = all_player_funds
    max_amount = funds[command.issuer.name] || 0

    begin
      amount = Integer(amount)
    rescue ArgumentError
      amount = max_amount
    end

    amount = max_amount if amount > max_amount

    if mates.count.positive?
      if amount.positive?
        if donations_available?(command.issuer)
          slice = (amount / mates.count.to_f).floor
            donation = @donations[command.issuer.name] = {receivers: [], time: monotonic_time }

          mates.each do |mate|
            RenRem.cmd("donate #{command.issuer.id} #{mate.id} #{slice}")

            page_player(mate.name, "#{command.issuer.name} has donated #{slice} credits to you.")
            donation[:receivers] << { name: mate.name, amount: slice, money: funds[mate.name] }
          end

          RenRem.cmd("pinfo")

          # FIXME: Sometimes this message is not delivered!
          page_player(command.issuer.name, "You have donated #{amount} credits to your team.")
        end
      else
        page_player(command.issuer.name, "Cannot donate nothing!")
      end
    else
      page_player(command.issuer.name, "You are the only one on your team!")
    end
  end

  # NOTE: If receiver has less (credits + donation) then when they were donated to, we decline un-donating from this player
  command(:undonate, aliases: [:ud], arguments: 0, help: "!undonate - Undo last donation (limited to 5 seconds)") do |command|
    donation = @donations[command.issuer.name]

    if donation
      taken_back = 0
      total_given = donation[:receivers].sum { |r| r[:amount] }
      funds = all_player_funds

      donation[:receivers].each do |receiver|
        next unless receiver[:name]
        next unless receiver[:amount]
        next unless receiver[:money]

        player = PlayerData.player(PlayerData.name_to_id(receiver[:name], exact_match: true))
        next unless player

        # Player has likely spent it, reject un-donate from them
        next if funds[player.name] <= receiver[:amount] + receiver[:money]

        RenRem.cmd("donate #{player.id} #{command.issuer.id} #{receiver[:amount]}")
        taken_back += receiver[:amount]
        page_player(player.name, "#{command.issuer.name} has un-donated #{receiver[:amount]} credits from you.")
      end

      if taken_back == total_given
        page_player(command.issuer.name, "You have un-undonated and received back #{taken_back} credits.")
      elsif taken_back == 0
        page_player(command.issuer.name, "Unable to un-donated, all receivers have have spent credits since you donated to them.")
      else
        page_player(command.issuer.name, "You have un-undonated and received back #{taken_back} of #{total_given} credits.")
      end

      @donations.delete(command.issuer.name)
    else
      page_player(command.issuer.name, "You have made no donations in the last #{@undonate_timeout} seconds or have already un-donated.")
    end
  end
end
