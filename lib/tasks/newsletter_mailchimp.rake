namespace :newsletter do
  namespace :mailchimp do
    desc "Enqueue pending newsletter subscribers for Mailchimp sync"
    task enqueue_pending: :environment do
      count = 0

      NewsletterSubscriber.mailchimp_pending.find_each do |subscriber|
        Newsletter::SyncSubscriberJob.perform_later(subscriber)
        count += 1
      end

      puts "Enqueued #{count} newsletter subscribers for Mailchimp sync."
    end
  end
end
