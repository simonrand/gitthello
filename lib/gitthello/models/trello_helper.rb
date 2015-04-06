module Gitthello
  class TrelloHelper
    attr_reader :list_to_schedule, :list_backlog, :list_done, :all_cards_at_github, :board

    # https://trello.com/docs/api/card/#put-1-cards-card-id-or-shortlink
    MAX_TEXT_LENGTH=16384
    TRUNCATION_MESSAGE = "... [truncated by gitthello]"
    GITHUB_LINK_LABEL = 'GitHub'
    IGNORE_CARDS_WITH_LABELS = ['Release']

    def initialize(token, dev_key, board_name)
      Trello.configure do |cfg|
        cfg.member_token         = token
        cfg.developer_public_key = dev_key
      end
      @board_name = board_name
    end

    def setup
      @board = retrieve_board

      @list_to_schedule = @board.lists.select { |a| a.name == 'To Schedule' }.first
      raise "Missing Trello To Schedule list" if list_to_schedule.nil?

      @all_cards_at_github = all_cards_at_github
      puts "Found #{@all_cards_at_github.count} cards already at GitHub"
      self
    end

    def has_card?(milestone)
      @all_cards_at_github.detect do |card|
        card[:github_details].url == milestone["html_url"]
      end
    end

    def create_to_schedule_card(name, desc, milestone_url, due_on)
      create_card_in_list(name, desc, milestone_url, list_to_schedule.id, due_on)
    end

    def new_cards_to_github(github_helper)
      all_cards_not_at_github.each do |card|
        puts "Adding milestone to #{get_repo_name_from_card_title(card.name)} repo"
        repo_name = get_repo_name_from_card_title(card.name)
        if milestone = github_helper.create_milestone(card.name.sub(/^\[.*\]\s?/, ''), card.desc, card.due, repo_name)
          github_helper.add_trello_url(milestone, card.url)
          card.add_attachment(milestone.html_url, GITHUB_LINK_LABEL)
          unless(repo_name)
            # Update card title to include repo name
            card.name = "[#{repo_name}] #{card.name}"
            card.save
          end
        else
          puts 'Failed to add GitHub milestone.'
        end
      end
    end

    private

    def obtain_github_details(card)
      card.attachments.select do |a|
        a.name == GITHUB_LINK_LABEL || a.url =~ /https:\/\/github.com.*issues.*/
      end.first
    end

    def retrieve_board
      Trello::Board.all.select { |b| b.name == @board_name }.first
    end

    def create_card_in_list(name, desc, url, list_id, due_on = nil)
      Trello::Card.
        create(:name => truncate_text(name), :list_id => list_id,
               :desc => truncate_text(desc), :due => due_on).tap do |card|
        card.add_attachment(url, GITHUB_LINK_LABEL)
      end
    end

    def get_repo_name_from_card_title(card_title)
      if matches = card_title.match(/^\[(.*)\]\s?/)
        matches[1]
      end
    end

    def all_cards_not_at_github
      board.lists.map do |a|
        a.cards.map do |card|
          obtain_github_details(card).nil? ? card : nil
        end.compact
      end.flatten.reject do |card|
        # Ignore cards in the IGNORE_CARDS_WITH_LABELS list
        # or cards with no repo name
        !(card.labels.map(&:name) & IGNORE_CARDS_WITH_LABELS).empty? || !get_repo_name_from_card_title(card.name)
      end
    end

    def all_cards_at_github
      board.lists.map do |a|
        a.cards.map do |card|
          github_details = obtain_github_details(card)
          github_details.nil? ? nil : { :card => card, :github_details => github_details }
        end.compact
      end.flatten
    end

    def truncate_text(text)
      if text && text.length > MAX_TEXT_LENGTH
        text[0, MAX_TEXT_LENGTH - TRUNCATION_MESSAGE.length] + TRUNCATION_MESSAGE
      else
        text
      end
    end
  end
end
