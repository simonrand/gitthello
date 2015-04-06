module Gitthello
  class Board
    attr_reader :trello_helper, :github_helper

    def initialize(board_config)
      @config = board_config.clone
      @github_helper = GithubHelper.new(Gitthello.configuration.github.token,
                                        @config.default_repo_for_new_cards,
                                        @config.repos_to_consider)
      @trello_helper = TrelloHelper.new(Gitthello.configuration.trello.token,
                                        Gitthello.configuration.trello.dev_key,
                                        @config.name)
    end

    def synchronize
      puts "==> Handling Board: #{@config.name}"
      @trello_helper.setup
      @github_helper.retrieve_milestones
      @github_helper.new_milestones_to_trello(@trello_helper)
      @trello_helper.new_cards_to_github(@github_helper)
    end

    def name
      @config.name
    end
  end
end
