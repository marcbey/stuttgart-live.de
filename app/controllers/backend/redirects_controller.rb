module Backend
  class RedirectsController < BaseController
    PER_PAGE = 25

    before_action :require_admin!
    before_action :set_filters
    before_action :set_redirect, only: %i[edit update recheck]

    def index
      load_list
      @selected_redirect = if ActiveModel::Type::Boolean.new.cast(params[:new])
        LegacyRedirect.new(status: "redirect", origin: "manual")
      elsif params[:redirect_id].present?
        LegacyRedirect.find_by(id: params[:redirect_id])
      else
        @redirects.first
      end
    end

    def new
      @redirect = LegacyRedirect.new(status: "redirect", origin: "manual")
      return render_editor_panel(@redirect) if turbo_frame_request?

      redirect_to backend_redirects_path(@list_context.merge(new: "1"))
    end

    def create
      @redirect = LegacyRedirect.new
      assign_decision(@redirect)

      if @redirect.save
        respond_with_editor_state(@redirect, notice: "Weiterleitung wurde angelegt.")
      else
        render_invalid_state(@redirect)
      end
    end

    def edit
      return render_editor_panel(@redirect) if turbo_frame_request?

      redirect_to backend_redirects_path(@list_context.merge(redirect_id: @redirect.id))
    end

    def update
      saved = @redirect.with_lock do
        assign_decision(@redirect)
        @redirect.save
      end

      if saved
        respond_with_editor_state(@redirect, notice: "Weiterleitung wurde gespeichert.")
      else
        render_invalid_state(@redirect)
      end
    end

    def recheck
      result = @redirect.with_lock do
        @redirect.update_columns(checked_at: nil) unless @redirect.manual?
        LegacyRedirects::Resolver.call(path: @redirect.source_path, query: "")
      end
      @redirect.reload
      message = case result.status
      when :redirect then "Prüfung abgeschlossen: öffentliches Ziel bestätigt."
      when :disabled then "Prüfung abgeschlossen: manuelle Sperre bleibt erhalten."
      else "Prüfung abgeschlossen: kein öffentliches Ziel gefunden."
      end
      respond_with_editor_state(@redirect, notice: message)
    end

    private

      def set_filters
        @query_filter = params[:query].to_s.strip.presence
        @status_filter = params[:status].presence_in(LegacyRedirect::STATUSES)
        @origin_filter = params[:origin].presence_in(LegacyRedirect::ORIGINS)
        @page_number = [ params[:page].to_i, 1 ].max
        @list_context = {
          query: @query_filter,
          status: @status_filter,
          origin: @origin_filter,
          page: (@page_number if @page_number > 1)
        }.compact
      end

      def set_redirect
        @redirect = LegacyRedirect.find(params[:id])
      end

      def load_list
        relation = LegacyRedirect.includes(:target).order(:source_path, :id)
        relation = relation.where(status: @status_filter) if @status_filter
        relation = relation.where(origin: @origin_filter) if @origin_filter
        if @query_filter
          token = "%#{LegacyRedirect.sanitize_sql_like(@query_filter.downcase)}%"
          relation = relation.where(
            "LOWER(source_path) LIKE :token OR LOWER(COALESCE(target_path, '')) LIKE :token OR LOWER(COALESCE(source_metadata->>'title', '')) LIKE :token",
            token: token
          )
        end
        @total_count = relation.count
        @total_pages = [ (@total_count.to_f / PER_PAGE).ceil, 1 ].max
        @redirects = relation.offset((@page_number - 1) * PER_PAGE).limit(PER_PAGE)
      end

      def assign_decision(rule)
        rule.assign_attributes(redirect_params)
        rule.origin = rule.status == "unresolved" ? "automatic" : "manual"
        rule.match_reason = rule.manual? ? "manual_decision" : nil
        rule.score = nil
        if rule.status == "unresolved"
          rule.target = nil
          rule.target_path = nil
          rule.checked_at = nil
          rule.resolution_version = nil
        end
      end

      def redirect_params
        params.require(:legacy_redirect).permit(:source_path, :source_kind, :destination, :status)
      end

      def render_editor_panel(rule)
        render partial: "backend/redirects/editor_frame", locals: editor_locals(rule)
      end

      def editor_locals(rule)
        { rule: rule, list_context: @list_context, page_number: @page_number }
      end

      def list_locals(rule)
        { redirects: @redirects, selected_redirect: rule, total_count: @total_count,
          total_pages: @total_pages, list_context: @list_context, page_number: @page_number }
      end

      def render_invalid_state(rule)
        flash.now[:alert] = "Weiterleitung konnte nicht gespeichert werden. Bitte Eingaben prüfen."
        respond_to do |format|
          format.html do
            load_list
            @selected_redirect = rule
            render :index, status: :unprocessable_entity
          end
          format.turbo_stream do
            render turbo_stream: [
              turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace("redirect_editor", partial: "backend/redirects/editor_frame", locals: editor_locals(rule))
            ], status: :unprocessable_entity
          end
        end
      end

      def respond_with_editor_state(rule, notice:)
        respond_to do |format|
          format.html do
            redirect_to backend_redirects_path(@list_context.merge(redirect_id: rule.id)), notice: notice
          end
          format.turbo_stream do
            load_list
            flash.now[:notice] = notice
            render turbo_stream: [
              turbo_stream.update("flash-messages", partial: "layouts/flash_messages"),
              turbo_stream.replace("redirect_topbar_controls", partial: "backend/redirects/topbar_controls", locals: { rule: rule, list_context: @list_context }),
              turbo_stream.replace("redirects_list", partial: "backend/redirects/redirects_list", locals: list_locals(rule)),
              turbo_stream.replace("redirect_editor", partial: "backend/redirects/editor_frame", locals: editor_locals(rule))
            ]
          end
        end
      end
  end
end
