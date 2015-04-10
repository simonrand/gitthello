module Gitthello
  class TrelloHelper
    attr_reader :list_to_schedule, :list_backlog, :list_done, :all_cards_at_github, :all_cards_not_at_github, :all_cards_to_put_on_github, :all_release_cards, :board

    # https://trello.com/docs/api/card/#put-1-cards-card-id-or-shortlink
    MAX_TEXT_LENGTH=16384
    TRUNCATION_MESSAGE = "... [truncated by gitthello]"
    GITHUB_LINK_LABEL = 'GitHub'
    RELEASE_LABEL = 'Release'
    IGNORE_CARDS_WITH_LABELS = [RELEASE_LABEL, 'Key Date', 'Important Date']

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

      @all_cards_at_github, @all_cards_not_at_github = all_cards
      @all_cards_to_put_on_github = all_cards_to_put_on_github
      @all_release_cards = all_release_cards

      puts "Found #{@all_cards_at_github.count} cards already at GitHub"
      puts "Found #{@all_cards_not_at_github.count} cards not at GitHub"
      puts "Found #{@all_cards_to_put_on_github.count} cards to put on GitHub"
      puts "Found #{@all_release_cards.count} release cards"
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
      @all_cards_to_put_on_github.each do |card|
        puts "Adding milestone to #{get_repo_name_from_card_title(card.name)} repo"
        repo_name = get_repo_name_from_card_title(card.name)
        if milestone = github_helper.create_milestone(card.name.sub(/^\[.*\]\s?/, ''), card.desc, card.due, repo_name)
          github_helper.add_trello_url(milestone, card.url)
          card.add_attachment(milestone.html_url, GITHUB_LINK_LABEL)
          unless(repo_name)
            # Update card title to include repo name and (0/0) count
            card.name = "[#{repo_name}] #{card.name} (0/0)"
            card.save
          end
        else
          puts 'Failed to add GitHub milestone.'
        end
      end
    end

    def update_card_name_with_issue_count(card, closed_issues, total_issues)
      puts "Updating #{card.name} with new issue count"
      pattern = /\(\d+\/\d+\)$/
      new_count = "(#{closed_issues}/#{total_issues})"
      if card.name.match(pattern)
        card.name = card.name.sub(pattern, new_count)
      else
        card.name = "#{card.name.rstrip} #{new_count}"
      end
      puts "Saving #{card.name}"
      card.save
    end

    def update_release_issue_counts
      puts 'Updating release card issue counts'
      pattern = /(https:\/\/trello.com\/c\/.*\/\d+)-.*/
      @all_release_cards.each do |card|
        attachments = obtain_trello_card_attachments(card.attachments)
        puts "Release #{card.name} has #{attachments.length} sub cards"

        total_closed_issues, total_issues = attachments.map do |attachment|
          @all_cards_at_github.map do |card|
            card[:card]
          end.detect do |card|
            card.url.match(pattern)[1] == attachment.url.match(pattern)[1]
          end.name.match(/\((\d+)\/(\d+)\)$/)[1..2].map(&:to_i)
        end.transpose.map { |x| x.reduce(:+) }

        update_card_name_with_issue_count(card, total_closed_issues, total_issues) if total_closed_issues && total_issues
      end
    end

    private

    def obtain_github_details(card)
      puts "Obtaining GitHub details for #{card.name}"
      repeatthis do
        card.attachments.select do |a|
          a.name == GITHUB_LINK_LABEL || a.url =~ /https:\/\/github.com.*issues.*/
        end.first
      end
    end

    def obtain_trello_card_attachments(attachments)
      puts "Obtaining Trello card attachments"
      attachments.select do |a|
        a.url =~ /https:\/\/trello.com\/c\/.*/
      end
    end

    def retrieve_board
      puts "Retrieving Trello Board"
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

    def all_cards
      puts "Retrieving all cards"
      all_cards = board.lists.map do |list|
        list.cards.map do |card|
          github_details = get_repo_name_from_card_title(card.name) ? obtain_github_details(card) : nil
          { :card => card, :github_details => github_details }
        end
      end.flatten

      all_cards.partition do |card|
        card[:github_details].present?
      end
    end

    def all_cards_to_put_on_github
      puts "Retrieving all cards to put on GitHub"
      @all_cards_not_at_github.map do |card|
        card[:card]
      end.select do |card|
        get_repo_name_from_card_title(card.name)
      end
    end

    def all_release_cards
      puts "Retrieving all release cards"
      @all_cards_not_at_github.map do |card|
        card[:card]
      end.select do |card|
        repeatthis do
          card.labels.map(&:name).include?(RELEASE_LABEL)
        end
      end
    end

    def truncate_text(text)
      if text && text.length > MAX_TEXT_LENGTH
        text[0, MAX_TEXT_LENGTH - TRUNCATION_MESSAGE.length] + TRUNCATION_MESSAGE
      else
        text
      end
    end

    def repeatthis(cnt=5,&block)
      last_exception = nil
      cnt.times do
        begin
          return yield
        rescue Exception => e
          last_exception = e
          sleep 0.1
          next
        end
      end
      raise last_exception
    end
  end
end
