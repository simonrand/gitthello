desc "Synchronize Github and Trello"
task :sync do
  Gitthello::Sync.new.synchronize
end
