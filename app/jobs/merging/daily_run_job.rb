module Merging
  class DailyRunJob < ApplicationJob
    queue_as :default

    def perform
      return unless AppSetting.daily_merge_import_enabled?

      ImportSource.ensure_supported_sources!

      Backend::ImportSources::MergeRunStarter.new.call(
        run_metadata: {
          "triggered_by" => "scheduler",
          "schedule_name" => "daily_merge_run"
        }
      )
    end
  end
end
