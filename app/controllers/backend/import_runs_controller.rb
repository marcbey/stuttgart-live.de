module Backend
  class ImportRunsController < BaseController
    helper Backend::ImportSourcesHelper

    before_action :set_import_run, only: [ :show, :add_filtered_city, :remove_whitelist_city ]

    def show
      @run_errors = @import_run.import_run_errors.order(created_at: :desc)
    end

    def add_filtered_city
      city = params[:city].to_s.strip
      if city.blank?
        redirect_to backend_import_run_path(@import_run), alert: "Keine Stadt uebergeben."
        return
      end

      unless allowed_filtered_city?(city)
        redirect_to backend_import_run_path(@import_run), alert: "Diese Stadt ist für den Run nicht als aussortiert erfasst."
        return
      end

      move_filtered_city_to_whitelist!(city)
      notice = "'#{city}' wurde zur Ortsliste hinzugefügt."

      redirect_to backend_import_run_path(@import_run), notice: notice
    end

    def remove_whitelist_city
      city = params[:city].to_s.strip
      if city.blank?
        redirect_to backend_import_run_path(@import_run), alert: "Keine Stadt uebergeben."
        return
      end

      unless city_in_whitelist?(city)
        redirect_to backend_import_run_path(@import_run), alert: "Diese Stadt ist nicht in der Ortsliste enthalten."
        return
      end

      move_whitelist_city_to_filtered!(city)
      notice = "'#{city}' wurde aus der Ortsliste entfernt."

      redirect_to backend_import_run_path(@import_run), notice: notice
    end

    private

    def set_import_run
      @import_run = ImportRun.includes(:import_source, :import_run_errors, llm_genre_grouping_snapshot: :groups).find(params[:id])
    end

    def allowed_filtered_city?(city)
      filtered_out_cities_from_run(@import_run).any? { |candidate| same_city?(candidate, city) }
    end

    def city_in_whitelist?(city)
      whitelist_cities(@import_run.import_source).any? { |entry| same_city?(entry, city) }
    end

    def move_filtered_city_to_whitelist!(city)
      source = @import_run.import_source

      ImportSource.transaction do
        @import_run.lock!
        source.lock!
        config = import_source_config_for(source)
        whitelist = whitelist_cities(source)
        filtered = filtered_out_cities_from_run(@import_run)

        unless whitelist.any? { |entry| same_city?(entry, city) }
          whitelist << city
        end

        filtered.reject! { |entry| same_city?(entry, city) }

        config.location_whitelist = whitelist
        config.save!
        persist_filtered_out_cities!(filtered)
      end
    end

    def move_whitelist_city_to_filtered!(city)
      source = @import_run.import_source

      ImportSource.transaction do
        @import_run.lock!
        source.lock!
        config = import_source_config_for(source)
        whitelist = whitelist_cities(source)
        filtered = filtered_out_cities_from_run(@import_run)

        whitelist.reject! { |entry| same_city?(entry, city) }
        filtered << city unless filtered.any? { |entry| same_city?(entry, city) }

        config.location_whitelist = whitelist
        config.save!
        persist_filtered_out_cities!(filtered)
      end
    end

    def import_source_config_for(source)
      source.import_source_config || source.build_import_source_config
    end

    def whitelist_cities(source)
      source
        .configured_location_whitelist
        .map { |entry| entry.to_s.strip }
        .reject(&:blank?)
        .uniq
    end

    def same_city?(left, right)
      left.to_s.strip.casecmp?(right.to_s.strip)
    end

    def filtered_out_cities_from_run(run)
      metadata = run.metadata.is_a?(Hash) ? run.metadata.deep_stringify_keys : {}
      Array(metadata["filtered_out_cities"])
        .map { |entry| entry.to_s.strip }
        .reject(&:blank?)
        .uniq
    end

    def persist_filtered_out_cities!(cities)
      metadata = @import_run.metadata.is_a?(Hash) ? @import_run.metadata.deep_stringify_keys : {}
      metadata["filtered_out_cities"] = cities.map(&:to_s).map(&:strip).reject(&:blank?).uniq.sort
      @import_run.update!(metadata: metadata)
    end
  end
end
