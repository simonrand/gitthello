module Gitthello
  class GithubHelper
    attr_reader :milestone_bucket

    def initialize(oauth_token, default_repo_for_new_cards, repos_to_consider)
      @github            = Github.new(:oauth_token => oauth_token)
      @user, @repo       = default_repo_for_new_cards.split(/\//)
      @repos_to_consider = repos_to_consider
    end

    def create_milestone(title, desc, due, repo = @repo)
      begin
        @github.issues.milestones.
          create( :user => @user, :repo => repo, :title => title, :description => desc, :due_on => due)
        rescue Github::Error::GithubError => e
          puts e.message
          false
      end
    end

    def add_trello_url(milestone, url)
      owner, repo, number = repo_owner(milestone), repo_name(milestone), milestone.number
      description = milestone.description || ""

      unless description =~ /\[Trello Card\]/ or
          description =~ /\[Added by trello\]/
        repeatthis do
          @github.issues.milestones.
            update(owner, repo, number.to_i,
                 :description => description + "\n\n\n[Trello Card](#{url})")
        end
      end
    end

    def retrieve_milestone(owner, name, number)
      @github.issues.milestones.get(owner, name, number)
    end

    def retrieve_milestones
      @milestone_bucket = []

      @repos_to_consider.split(/,/).map { |a| a.split(/\//)}.
        each do |repo_owner,repo_name|
          puts "Checking #{repo_owner}/#{repo_name}"
          repeatthis do
            @github.issues.milestones.
              list(:user => repo_owner, :repo => repo_name, :state => 'open',
                   :per_page => 100).
              sort_by { |a| a.number.to_i }
          end.each do |milestone|
            @milestone_bucket << [repo_name,milestone]
          end
      end

      puts "Found #{@milestone_bucket.count} #{'milestone'.pluralize(@milestone_bucket.count)}"
    end

    def new_milestones_to_trello(trello_helper)

      puts '==> Adding new to Trello & updating existing cards in Trello'

      # TODO Update should happen elsewhere

      existing_milestones_with_cards = 0
      milestones_without_cards = 0

      milestone_bucket.each do |repo_name, milestone|
        if existing_card = trello_helper.has_card?(milestone)
          existing_milestones_with_cards += 1

          if card_and_milestone_dates_differ?(existing_card[:card].due, milestone.due_on)
            # Update milestone with date from Trello card
            owner, repo, number = repo_owner(milestone), repo_name(milestone), milestone.number
            repeatthis do
              @github.issues.milestones.
                update(owner, repo, number.to_i,
                     :due_on => existing_card[:card].due.to_date)
            end
          end
          repeatthis do
            # Update card with milestone issue count
            trello_helper.update_card_name_with_issue_count(existing_card[:card], milestone.closed_issues, milestone.closed_issues + milestone.open_issues)
          end
        else
          # Create card for milestone
          milestones_without_cards += 1
          prefix = repo_name.downcase
          total_issues = milestone.closed_issues + milestone.open_issues

          card = trello_helper.
            create_to_schedule_card("[%s] %s (%d/%d)" %
              [prefix, milestone.title, milestone.closed_issues, total_issues],
              milestone.description, milestone.html_url, milestone.url, milestone.due_on)
          add_trello_url(milestone, card.url)
        end
      end

      puts "Found #{existing_milestones_with_cards} milestones with cards"
      puts "Found #{milestones_without_cards} milestones without cards (and added them)"
    end

    private

    def repo_owner(milestone)
      # assumes the that the url is something like:
      #   https://api.github.com/repos/<repo_owner>/<repo_name>/milestones/<Title>
      milestone["url"].split("/")[-4]
    end

    def repo_name(milestone)
      # assumes the that the url is something like:
      #   https://api.github.com/repos/<repo_owner>/<repo_name>/milestones/<Title>
      milestone["url"].split("/")[-3]
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

    def card_and_milestone_dates_differ?(card_date, milestone_date)
      if card_date.nil? && milestone_date.nil?
        false
      elsif card_date.present? && (milestone_date.nil? || card_date.to_date.beginning_of_day != milestone_date.to_date.beginning_of_day)
          true
      elsif milestone_date.present? && (card_date.nil? || milestone_date.to_date.beginning_of_day != card_date.to_date.beginning_of_day)
          true
      else
        false
      end
    end
  end
end
