module Gitthello
  class TrelloHelper
    attr_reader :list_to_schedule, :list_backlog, :list_done, :all_cards_at_github, :all_cards_not_at_github, :all_cards_to_put_on_github, :all_release_cards, :board

    # https://trello.com/docs/api/card/#put-1-cards-card-id-or-shortlink
    MAX_TEXT_LENGTH=16384
    TRUNCATION_MESSAGE = "... [truncated by gitthello]"
    GITHUB_LINK_LABEL = 'GitHub'
    GITHUB_API_LINK_LABEL = 'GitHub API'
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

    def create_to_schedule_card(name, desc, milestone_url, milestone_api_url, due_on)
      create_card_in_list(name, desc, milestone_url, milestone_api_url, list_to_schedule.id, due_on)
    end

    def new_cards_to_github(github_helper)
      puts '==> Adding new Trello cards to GitHub'

      @all_cards_to_put_on_github.each do |card|
        puts "Adding milestone to #{get_repo_name_from_card_title(card.name)} repo"
        repo_name = get_repo_name_from_card_title(card.name)
        if milestone = github_helper.create_milestone(card.name.sub(/^\[.*\]\s?/, ''), card.desc, card.due, repo_name)
          github_helper.add_trello_url(milestone, card.url)
          # Add GitHub web url
          card.add_attachment(milestone.html_url, GITHUB_LINK_LABEL)
          # Add GitHub API url (used when the milestone is closed)
          # FIXME: is the API url is available at this point?
          card.add_attachment(milestone.url, GITHUB_API_LINK_LABEL)
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

    def update_closed_milestones(github_helper)
      puts '==> Updating closed milestones'

      all_milestone_urls = github_helper.milestone_bucket.map do |milestone|
        milestone[1].url
      end

      @all_cards_at_github.each do |card|
        if card[:github_api_details] && !all_milestone_urls.include?(card[:github_api_details].url)

          # puts "Found closed milestone: #{card[:card].name}"
          # puts card[:github_api_details].url

          milestone_details = card[:github_api_details].url.match(/https:\/\/api.github.com\/repos\/(.*)\/(.*)\/milestones\/(\d+)$/)

          milestone = github_helper.retrieve_milestone(milestone_details[1], milestone_details[2], milestone_details[3])

          update_card_name_with_issue_count(card[:card], milestone.closed_issues, milestone.closed_issues + milestone.open_issues)
        end
      end
    end

    def update_card_name_with_issue_count(card, closed_issues, total_issues)

      pattern = /\(\d+\/\d+\)$/
      new_count = "(#{closed_issues}/#{total_issues})"
      update_name = false

      if card.name.match(pattern)
        new_name = card.name.sub(pattern, new_count)
        if card.name != new_name
          card.name = new_name
          update_name = true
        end
      else
        card.name = "#{card.name.rstrip} #{new_count}"
        update_name = true
      end

      if update_name
        puts "Updating #{card.name} with new issue count"
        card.save
      end
    end

    def update_release_issue_counts
      puts '==> Updating release card issue counts'

      pattern = /(https:\/\/trello.com\/c\/.*\/\d+)-.*/
      @all_release_cards.each do |card|
        attachments = obtain_trello_card_attachments(card.attachments)
        puts "Release #{card.name} has #{attachments.length} sub cards"

        total_closed_issues, total_issues = attachments.map do |attachment|
          sub_card = @all_cards_at_github.map do |card|
            card[:card]
          end.detect do |card|
            card.url.match(pattern)[1] == attachment.url.match(pattern)[1]
          end

          sub_card ||= get_trello_card(get_trello_card_id_from_url(attachment.url))

          sub_card.name.match(/\((\d+)\/(\d+)\)$/)[1..2].map(&:to_i)
        end.transpose.map { |x| x.reduce(:+) }

        update_card_name_with_issue_count(card, total_closed_issues, total_issues) if total_closed_issues && total_issues
      end
    end

    private

    def get_trello_card(card_id)
      Trello::Card.find(card_id)
    end

    def get_trello_card_id_from_url(url)
      url.match(/https:\/\/trello.com\/c\/(.+)\/.+$/)[1]
    end

    def obtain_github_details(card)
      # puts "Obtaining GitHub details for #{card.name}"

      attachments = card.attachments
      github_details = attachments.select do |a|
        a.name == GITHUB_LINK_LABEL
      end.first
      github_api_details = attachments.select do |a|
        a.name == GITHUB_API_LINK_LABEL
      end.first

      {
        :github_details => github_details,
        :github_api_details => github_api_details
      }
    end

    def obtain_trello_card_attachments(attachments)
      # puts "Obtaining Trello card attachments"
      attachments.select do |a|
        a.url =~ /https:\/\/trello.com\/c\/.*/
      end
    end

    def retrieve_board
      puts "==> Retrieving Trello Board"
      Trello::Board.all.select { |b| b.name == @board_name }.first
    end

    def create_card_in_list(name, desc, url, api_url, list_id, due_on = nil)
      Trello::Card.
        create(:name => truncate_text(name), :list_id => list_id,
               :desc => truncate_text(desc), :due => due_on).tap do |card|
        card.add_attachment(url, GITHUB_LINK_LABEL)
        card.add_attachment(api_url, GITHUB_API_LINK_LABEL)
      end
    end

    def get_repo_name_from_card_title(card_title)
      if matches = card_title.match(/^\[(.*)\]\s?/)
        matches[1]
      end
    end

    def all_cards
      puts 'Retrieving all cards'
      all_cards = board.lists.map do |list|
        list.cards.map do |card|
          github_details = get_repo_name_from_card_title(card.name) ? obtain_github_details(card) : nil
          if github_details
            { :card => card, :github_details => github_details[:github_details], :github_api_details => github_details[:github_api_details] }
          else
            { :card => card }
          end
        end
      end.flatten

      all_cards.partition do |card|
        card[:github_details].present?
      end
    end

    def all_cards_to_put_on_github
      puts 'Retrieving all cards to put on GitHub'
      @all_cards_not_at_github.map do |card|
        card[:card]
      end.select do |card|
        get_repo_name_from_card_title(card.name)
      end
    end

    def all_release_cards
      puts 'Retrieving all release cards'
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
