namespace :ramps do
  desc "HEAD every ramp URL and print its status. Manual: not part of tests or CI"
  task check: :environment do
    Ramps::LinkCheck.run
  end
end
