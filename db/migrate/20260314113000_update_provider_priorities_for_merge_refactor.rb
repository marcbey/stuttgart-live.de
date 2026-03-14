class UpdateProviderPrioritiesForMergeRefactor < ActiveRecord::Migration[8.1]
  PRIORITIES = {
    "easyticket" => 0,
    "eventim" => 10,
    "reservix" => 20
  }.freeze

  def up
    PRIORITIES.each do |source_type, priority_rank|
      execute <<~SQL.squish
        UPDATE provider_priorities
        SET priority_rank = #{priority_rank}
        WHERE source_type = #{quote(source_type)}
      SQL
    end
  end

  def down
    execute <<~SQL.squish
      UPDATE provider_priorities SET priority_rank = 10 WHERE source_type = 'reservix'
    SQL
    execute <<~SQL.squish
      UPDATE provider_priorities SET priority_rank = 20 WHERE source_type = 'eventim'
    SQL
  end
end
