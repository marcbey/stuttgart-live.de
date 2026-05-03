require "test_helper"

class Importing::DailyRunJobTest < ActiveJob::TestCase
  teardown do
    AppSetting.reset_cache!
  end

  test "enqueues active provider import jobs when scheduler is enabled" do
    AppSetting.create!(key: AppSetting::DAILY_RAW_IMPORT_ENABLED_KEY, value: true)

    assert_enqueued_jobs 3 do
      Importing::DailyRunJob.perform_now
    end
  end

  test "does not enqueue provider import jobs when scheduler is disabled" do
    AppSetting.create!(key: AppSetting::DAILY_RAW_IMPORT_ENABLED_KEY, value: false)

    assert_no_enqueued_jobs do
      Importing::DailyRunJob.perform_now
    end
  end
end
