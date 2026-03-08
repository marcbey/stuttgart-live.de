class RemoveMissingGenreFromEventCompletenessFlags < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      WITH recalculated AS (
        SELECT
          events.id,
          COALESCE(
            (
              SELECT jsonb_agg(flag)
              FROM jsonb_array_elements_text(events.completeness_flags) AS flag
              WHERE flag <> 'missing_genre'
            ),
            '[]'::jsonb
          ) AS filtered_flags
        FROM events
        WHERE events.completeness_flags @> '["missing_genre"]'::jsonb
      )
      UPDATE events
      SET
        completeness_flags = recalculated.filtered_flags,
        completeness_score = ROUND(((7 - jsonb_array_length(recalculated.filtered_flags))::numeric / 7) * 100)::integer,
        updated_at = CURRENT_TIMESTAMP
      FROM recalculated
      WHERE events.id = recalculated.id
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "missing_genre removal cannot be reversed automatically"
  end
end
