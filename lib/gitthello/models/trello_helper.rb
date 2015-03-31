module Gitthello
  class TrelloHelper
    attr_reader :list_to_schedule, :list_backlog, :list_done, :github_urls, :board

    # https://trello.com/docs/api/card/#put-1-cards-card-id-or-shortlink
    MAX_TEXT_LENGTH=16384
    TRUNCATION_MESSAGE = "... [truncated by gitthello]"
    GITHUB_LINK_LABEL = 'GitHub'
    IGNORE_CARDS = [/^\[RELEASE\].*$/]

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

      @github_urls = all_github_urls
      puts "Found #{@github_urls.count} github urls"
      self
    end

    # def archive_done
    #   old_pos = @list_done.pos
    #   @list_done.name = "Done KW#{Time.now.strftime('%W')}"
    #   @list_done.save
    #   @list_done.close!

    #   @list_done = Trello::List.create(:name => "Done", :board_id=> @board.id)
    #   @list_done.pos = old_pos+1
    #   @list_done.save
    # end

    def has_card?(milestone)
      @github_urls.include?(milestone["html_url"])
    end

    def create_todo_card(name, desc, milestone_url, due_on)
      create_card_in_list(name, desc, milestone_url, list_to_schedule.id, due_on)
    end

    # def create_backlog_card(name, desc, milestone_url)
    #   create_card_in_list(name, desc, milestone_url, list_backlog.id)
    # end

    #
    # Close github issues that have been moved to the done list but only
    # if the ticket has been reopened, i.e. updated_at timestamp is
    # newer than the card.
    #
    # def close_issues(github_helper)
    #   list_done.cards.each do |card|
    #     github_details = obtain_github_details(card)
    #     next if github_details.nil?

    #     user,repo,_,number = github_details.url.split(/\//)[3..-1]
    #     issue = github_helper.get_issue(user,repo,number)

    #     if card.last_activity_date > DateTime.strptime(issue.updated_at)
    #       # if the card was moved more recently than the issue was updated,
    #       # then close the issue
    #       github_helper.close_issue(user,repo,number)
    #     else
    #       # if the issue was updated more recently than the card and it's
    #       # open, then move the card to the todo list, i.e. the issue
    #       # was reopened.
    #       card.move_to_list(list_to_schedule) if issue.state == "open"
    #     end
    #   end
    # end

    # def move_cards_with_closed_issue(github_helper)
    #   board.lists.each do |list|
    #     next if list.id == list_done.id
    #     list.cards.each do |card|
    #       d = obtain_github_details(card)
    #       next if d.nil?
    #       user,repo,_,number = d.url.split(/\//)[3..-1]
    #       if github_helper.issue_closed?(user,repo,number)
    #         card.move_to_list(list_done)
    #         card.pos = "top"
    #         card.save
    #       end
    #     end
    #   end
    # end

    def new_cards_to_github(github_helper)
      all_cards_not_at_github.each do |card|
        milestone = github_helper.create_milestone(card.name.sub(/^\[.*\]\s?/, ''), card.desc, card.due)
        github_helper.add_trello_url(milestone, card.url)
        card.add_attachment(milestone.html_url, GITHUB_LINK_LABEL)
        repo_name = obtain_github_details(card).url.split(/\//)[4]
        unless(card.name.match(/^\[.+\].*$/))
          # Update card title to include repo name
          card.name = "[#{repo_name}] #{card.name}"
          card.save
        end
      end
    end

    def add_trello_link_to_milestones(github_helper)
      board.cards.each do |card|
        milestone = obtain_milestone_for_card(card, github_helper)
        next if issue.nil?

        github_helper.add_trello_url(milestone, card.url)
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

    def obtain_issue_for_card(card, github_helper)
      gd = obtain_github_details(card)
      return if gd.nil?

      user,repo,_,number = gd.url.split(/\//)[3..-1]
      github_helper.get_issue(user,repo,number)
    end

    def all_cards_not_at_github
      board.lists.map do |a|
        a.cards.map do |card|
          obtain_github_details(card).nil? ? card : nil
        end.compact
      end.flatten.reject do |card|
        # Ignore cards in the IGNORE_CARDS list
        IGNORE_CARDS.any? { |ignore| card.name =~ ignore }
      end
    end

    def all_github_urls
      board.lists.map do |a|
        a.cards.map do |card|
          github_details = obtain_github_details(card)
          github_details.nil? ? nil : github_details.url
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
