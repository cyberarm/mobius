mobius_plugin(name: "CoolHats", database_name: "cool_hats", version: "0.0.1") do
  on(:start) do
    @enabled = false
    @team_zero_hat = nil
    @team_one_hat = nil

    @script = "CDW_Tactical_Cupholder"
    @bone = "C Head"
    @player_selected_hat = {}

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
    @enabled = !@enabled

    @team_zero_hat = command.arguments.first
    @team_one_hat = command.arguments.last

    if @enabled
      PlayerData.player_list.each do |player|
        next unless can_wear_hat?(player) # keep hats off spectators and ghosts

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
    next unless @enabled

    page_player(command.issuer, "[CoolHats] Available hats:")
    @hats.each_slice(8).each do |subset|
      page_player(command.issuer, subset.join(", "))
    end
  end

  command(:hat, arguments: 1, help: "!hat <hat> - Choose your hat, unless admin has chosen teamed hats.") do |command|
    next unless @enabled

    if (hat = @hats.find { |h| h == command.arguments.first })
      @player_selected_hat[command.issuer] = hat

      remove_hat(player)
      wear_hat(player, select_hat(player)) if can_wear_hat?(player)

      page_player(player, "[CoolHats] Hat `#{hat}` selected.")
    else
      page_player(player, "[CoolHats] Hat `#{hat}` not found, see !hats for a list of available hats.")
    end
  end

  def can_wear_hat?(player)
    @enabled && player.team >= 0
  end

  def select_hat(player)
    # choose pseudo random hat based on player name
    hat = player.name.bytes.sum % @hats.size

    # choose hat based on team
    if player.team.zero? && (team_zero_hat = @hats.find { |h| h == @team_zero_hat })
      hat = team_zero_hat
    elsif player.team.positive? && (team_one_hat = @hats.find { |h| h == @team_one_hat })
      hat = team_one_hat
    # choose player's selected hat
    elsif (player_hat = @player_selected_hat.find { |key, _h| key == player }&.last)
      hat = player_hat
    end

    hat
  end

  def wear_hat(player, hat)
    return unless hat

    RenRem.cmd("attachscript #{player.id} #{@script} #{hat},#{@bone}")
  end

  def remove_hat(player)
    RenRem.cmd("unattachscript #{player.id} #{@script}")
  end
end
