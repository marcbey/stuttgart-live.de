class UpdateProviderPrioritiesOrder < ActiveRecord::Migration[8.1]
  PRIORITIES = {
    "easyticket" => 0,
    "reservix" => 10,
    "eventim" => 20
  }.freeze

  def up
    PRIORITIES.each do |source_type, priority_rank|
      priority = ProviderPriority.find_or_initialize_by(source_type: source_type)
      priority.priority_rank = priority_rank
      priority.active = true if priority.active.nil?
      priority.save!
    end
  end

  def down
    {
      "reservix" => 0,
      "easyticket" => 10,
      "eventim" => 20
    }.each do |source_type, priority_rank|
      priority = ProviderPriority.find_by(source_type: source_type)
      next unless priority

      priority.update!(priority_rank: priority_rank)
    end
  end
end
