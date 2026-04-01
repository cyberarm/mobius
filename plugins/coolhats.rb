mobius_plugin(name: "CoolHats", database_name: "cool_hats", version: "0.0.1") do
  on(:start) do
    @enabled = false
    @team_zero_hat = nil
    @team_one_hat = nil

    @script = "CDW_Tactical_Cupholder"
    @bone = "C Head"
    @player_selected_hat = {}

    @debug_hat_index = 0

    @hats = %w[
      animal-beaver
      animal-bee
      animal-bunny
      animal-cat
      animal-caterpil
      animal-chick
      animal-cow
      animal-crab
      animal-deer
      animal-dog
      animal-elephant
      animal-fish
      animal-fox
      animal-giraffe
      animal-hog
      animal-koala
      animal-lion
      animal-monkey
      animal-panda
      animal-parrot
      animal-penguin
      animal-pig
      animal-polar
      animal-tiger
    ]
  end

  on(:player_joined) do |player|
    wear_hat(player, select_hat(player)) if can_wear_hat?(player)
  end

  on(:created) do |hash|
    next unless hash[:type].downcase.strip.to_sym == :soldier
    next unless (player = PlayerData.player(PlayerData.name_to_id(hash[:name])))

    wear_hat(player, select_hat(player)) if can_wear_hat?(player)
  end

  command(:coolhats, arguments: 0..2, help: "!coolhats [[team zero] hat, [team_one_hat]] - Wear cool hats",
                     groups: %i[admin mod]) do |command|
    @team_zero_hat = @hats.find { |h| h == command.arguments.first }
    @team_one_hat = @hats.find { |h| h == command.arguments.last }

    @enabled = true if @team_zero_hat || @team_one_hat
    @enabled = !@enabled unless @team_zero_hat || @team_one_hat

    if @enabled
      PlayerData.player_list.each do |player|
        next unless can_wear_hat?(player) # keep hats off spectators and ghosts

        remove_hat(player)
        wear_hat(player, select_hat(player))

        page_player(player, "[CoolHats] Try out third person ;)")
      end

      page_player(command.issuer, "[CoolHats] On!")
    else
      PlayerData.player_list.each do |player|
        remove_hat(player)
      end

      page_player(command.issuer, "[CoolHats] Off.")
    end
  end

  command(:hats, arguments: 0, help: "!hats - List available hats") do |command|
    page_player(command.issuer, "[CoolHats] Available hats:")
    @hats.each_slice(8).each do |subset|
      page_player(command.issuer, subset.join(", "))
    end
  end

  command(:hat, arguments: 1, help: "!hat <hat> - Choose your hat, unless admin has chosen teamed hats.") do |command|
    if (hat = @hats.find { |h| h == command.arguments.first })
      @player_selected_hat[command.issuer] = hat

      remove_hat(command.issuer)
      wear_hat(command.issuer, select_hat(command.issuer)) if can_wear_hat?(command.issuer)

      page_player(command.issuer, "[CoolHats] Hat `#{hat}` selected.")
    else
      page_player(command.issuer, "[CoolHats] Hat `#{hat}` not found, see !hats for a list of available hats.")
    end
  end

  command(:debughats, arguments: 0, help: "!debughats - Cycle through all the hats to weed out any with issues.", groups: [:admin]) do |command|
    every(3) do
      message_player(command.issuer, "[CoolHats] Debug: #{@hats[@debug_hat_index]} [ID: #{@debug_hat_index}]")
      remove_hat(command.issuer)
      wear_hat(command.issuer, @hats[@debug_hat_index])
      @debug_hat_index = (@debug_hat_index + 1) % @hats.size
    end
  end

  def can_wear_hat?(player)
    @enabled && player.team >= 0
  end

  def select_hat(player)
    # choose pseudo random hat based on player name
    hat = @hats[player.name.bytes.sum % @hats.size]

    # choose hat based on team
    if player.team.zero? && @team_zero_hat
      hat = @team_zero_hat
    elsif player.team.positive? && @team_one_hat
      hat = @team_one_hat
    # choose player's selected hat
    elsif (player_hat = @player_selected_hat.find { |key, _h| key == player }&.last)
      hat = player_hat
    end

    hat
  end

  def wear_hat(player, hat)
    log "attachscript #{player.id} #{@script} #{hat},#{@bone}"

    return unless hat

    RenRem.cmd("attachscript #{player.id} #{@script} #{hat},#{@bone}")
  end

  def remove_hat(player)
    RenRem.cmd("unattachscript #{player.id} #{@script}")
  end
end
