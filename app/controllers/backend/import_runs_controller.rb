module Backend
  class ImportRunsController < BaseController
    helper Backend::ImportSourcesHelper

    def show
      @import_run = ImportRun.includes(:import_source, :import_run_errors).find(params[:id])
      @run_errors = @import_run.import_run_errors.order(created_at: :desc)
    end
  end
end
