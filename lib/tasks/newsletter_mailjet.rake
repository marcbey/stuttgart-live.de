namespace :newsletter do
  namespace :mailjet do
    desc "Enqueue pending newsletter subscribers for Mailjet sync"
    task enqueue_pending: :environment do
      count = 0

      NewsletterSubscriber.external_sync_pending.find_each do |subscriber|
        Newsletter::SyncSubscriberJob.perform_later(subscriber)
        count += 1
      end

      puts "Enqueued #{count} newsletter subscribers for Mailjet sync."
    end
  end
end
