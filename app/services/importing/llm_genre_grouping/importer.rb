require "digest"
require "json"

module Importing
  module LlmGenreGrouping
    class Importer
      RUN_STALE_AFTER = 4.hours
      RUN_HEARTBEAT_STALE_AFTER = 10.minutes
      PROMPT_VERSION = "v1"
      OUTPUT_SCHEMA_NAME = "llm_genre_grouping".freeze
      CONSOLIDATION_OUTPUT_SCHEMA_NAME = "llm_genre_grouping_consolidation".freeze
      OUTPUT_GROUPS_KEY = "groups".freeze
      MAX_SINGLE_CALL_GENRE_COUNT = 300
      MAX_SINGLE_CALL_INPUT_JSON_BYTES = 120_000
      FALLBACK_CHUNK_SIZE = 250
      INVALID_RESPONSE_MAX_ATTEMPTS = 3
      REPAIR_INVALID_RESPONSE_MAX_ATTEMPTS = 2
      INVALID_RESPONSE_ERROR_MESSAGE_LIMIT = 1_000
      CONTEXT_LIMIT_ERROR_PATTERN = /(context|maximum|too (?:large|long)|token|length|size)/i

      Result = Data.define(
        :selected_count,
        :skipped_count,
        :groups_count,
        :requests_count,
        :snapshot_id,
        :snapshot_key,
        :requested_group_count,
        :effective_group_count,
        :model,
        :canceled
      )
      RequestResult = Data.define(:groups, :request_payload, :raw_response, :requests_count)

      def initialize(
        run:,
        client: nil,
        logger: Importing::Logging.logger,
        snapshot_model: LlmGenreGroupingSnapshot
      )
        AppSetting.reset_cache!
        @run = run
        @client = client || OpenAi::ResponsesClient.new(model: AppSetting.llm_genre_grouping_model)
        @logger = logger
        @snapshot_model = snapshot_model
      end

      def call
        raw_genres = raw_distinct_genres
        selected_genres = normalize_distinct_genres(raw_genres)
        skipped_count = raw_genres.size - selected_genres.size
        selected_count = selected_genres.size
        requested_group_count = AppSetting.llm_genre_grouping_group_count
        effective_group_count = [ requested_group_count, selected_count ].min

        logger.info("[LlmGenreGroupingImporter] run_id=#{run.id} started genres=#{selected_count} skipped=#{skipped_count} target_groups=#{requested_group_count}")

        update_run_progress!(
          selected_count: selected_count,
          skipped_count: skipped_count,
          groups_count: 0,
          requests_count: 0,
          requested_group_count: requested_group_count,
          effective_group_count: effective_group_count,
          source_genres_count: selected_count,
          "execution_started_at" => Time.current.iso8601,
          "model" => client_model,
          "prompt_version" => PROMPT_VERSION
        )

        if selected_genres.empty?
          logger.info("[LlmGenreGroupingImporter] run_id=#{run.id} finished without genres")
          return Result.new(
            selected_count: 0,
            skipped_count: skipped_count,
            groups_count: 0,
            requests_count: 0,
            snapshot_id: nil,
            snapshot_key: nil,
            requested_group_count: requested_group_count,
            effective_group_count: 0,
            model: client_model,
            canceled: false
          )
        end

        check_stop_requested!(requests_count: 0)

        request_result = request_groups_with_fallback!(selected_genres, effective_group_count)

        check_stop_requested!(requests_count: request_result.requests_count)

        snapshot = persist_snapshot!(
          groups: request_result.groups,
          request_payload: request_result.request_payload,
          raw_response: request_result.raw_response,
          selected_count: selected_count,
          requested_group_count: requested_group_count,
          effective_group_count: effective_group_count
        )

        update_run_progress!(
          selected_count: selected_count,
          skipped_count: skipped_count,
          groups_count: snapshot.groups.size,
          requests_count: request_result.requests_count,
          requested_group_count: requested_group_count,
          effective_group_count: effective_group_count,
          source_genres_count: selected_count,
          "snapshot_id" => snapshot.id,
          "snapshot_key" => snapshot.snapshot_key,
          "model" => client_model,
          "prompt_version" => PROMPT_VERSION
        )

        logger.info("[LlmGenreGroupingImporter] run_id=#{run.id} succeeded groups=#{snapshot.groups.size} requests=#{request_result.requests_count} snapshot_id=#{snapshot.id}")

        Result.new(
          selected_count: selected_count,
          skipped_count: skipped_count,
          groups_count: snapshot.groups.size,
          requests_count: request_result.requests_count,
          snapshot_id: snapshot.id,
          snapshot_key: snapshot.snapshot_key,
          requested_group_count: requested_group_count,
          effective_group_count: effective_group_count,
          model: client_model,
          canceled: false
        )
      rescue Importing::StopRequested => e
        logger.info("[LlmGenreGroupingImporter] run_id=#{run.id} stopped cooperatively during fallback after requests=#{e.detail(:requests_count, 0)}")
        canceled_result(
          selected_count: selected_count,
          skipped_count: skipped_count,
          requested_group_count: requested_group_count,
          effective_group_count: effective_group_count,
          requests_count: e.detail(:requests_count, 0)
        )
      rescue StandardError => e
        logger.error("[LlmGenreGroupingImporter] run_id=#{run.id} failed: #{e.class}: #{e.message}")
        raise
      end

      private

      Error = Class.new(StandardError)
      attr_reader :client, :logger, :run, :snapshot_model

      def raw_distinct_genres
        EventLlmEnrichment.pluck(:genre)
          .flatten
          .compact
          .map(&:to_s)
          .uniq
      end

      def normalize_distinct_genres(genres)
        genres
          .map(&:strip)
          .reject(&:blank?)
          .uniq
          .sort
      end

      def request_groups_with_fallback!(genres, group_count)
        input_json = JSON.pretty_generate(genres)

        if genres.size > MAX_SINGLE_CALL_GENRE_COUNT
          logger.info("[LlmGenreGroupingImporter] run_id=#{run.id} switching to fallback because genres.count=#{genres.size}")
          return request_groups_via_fallback!(genres, group_count, fallback_reason: "genre_count_too_large")
        end

        if input_json.bytesize <= MAX_SINGLE_CALL_INPUT_JSON_BYTES
          begin
            groups, payload_entry, response_entry, attempts_count = request_groups_for_genres!(
              genres: genres,
              group_count: group_count,
              request_index: 1
            )

            return RequestResult.new(
              groups: groups,
              request_payload: {
                "mode" => "single",
                "requests" => [ payload_entry ]
              },
              raw_response: {
                "mode" => "single",
                "responses" => [ response_entry ]
              },
              requests_count: attempts_count
            )
          rescue OpenAi::ResponsesClient::Error => e
            raise unless context_limit_error?(e)

            logger.info("[LlmGenreGroupingImporter] run_id=#{run.id} switching to fallback after OpenAI size/context error: #{e.message}")
            return request_groups_via_fallback!(genres, group_count, fallback_reason: e.message)
          end
        end

        logger.info("[LlmGenreGroupingImporter] run_id=#{run.id} switching to fallback because input_json.bytes=#{input_json.bytesize}")
        request_groups_via_fallback!(genres, group_count, fallback_reason: "input_json_too_large")
      end

      def request_groups_via_fallback!(genres, group_count, fallback_reason:)
        request_payload_entries = []
        response_entries = []
        provisional_groups = []
        request_index = 0
        requests_count = 0

        genres.each_slice(FALLBACK_CHUNK_SIZE).with_index(1) do |chunk, chunk_index|
          check_stop_requested!(requests_count:)

          request_index += 1
          chunk_group_count = [ group_count, chunk.size ].min
          groups, payload_entry, response_entry, attempts_count = request_groups_for_genres!(
            genres: chunk,
            group_count: chunk_group_count,
            request_index: request_index,
            extra_payload: { "chunk_index" => chunk_index, "kind" => "chunk" }
          )
          requests_count += attempts_count
          request_payload_entries << payload_entry
          response_entries << response_entry
          provisional_group_offset = provisional_groups.size
          provisional_groups.concat(
            groups.each_with_index.map do |group, index|
              {
                "id" => provisional_group_offset + index + 1,
                "source_chunk_index" => chunk_index,
                "name" => group.fetch(:name),
                "genres" => group.fetch(:genres)
              }
            end
          )
        end

        check_stop_requested!(requests_count:)

        request_index += 1
        final_groups, payload_entry, response_entry, attempts_count = request_groups_for_provisional_groups!(
          provisional_groups: provisional_groups,
          group_count: group_count,
          request_index: request_index
        )
        requests_count += attempts_count
        request_payload_entries << payload_entry
        response_entries << response_entry

        RequestResult.new(
          groups: final_groups,
          request_payload: {
            "mode" => "fallback",
            "fallback_reason" => fallback_reason,
            "requests" => request_payload_entries
          },
          raw_response: {
              "mode" => "fallback",
              "responses" => response_entries
            },
            requests_count: requests_count
          )
      end

      def request_groups_for_genres!(genres:, group_count:, request_index:, extra_payload: {})
        prompt = request_input_for_genres(genres, group_count)
        payload_entry = {
          "request_index" => request_index,
          "kind" => extra_payload["kind"] || "genres",
          "group_count" => group_count,
          "genres" => genres
        }.merge(extra_payload.deep_stringify_keys)

        request_groups_for_prompt!(
          prompt: prompt,
          expected_genres: genres,
          expected_group_count: group_count,
          payload_entry: payload_entry
        )
      end

      def request_groups_for_provisional_groups!(provisional_groups:, group_count:, request_index:)
        payload_entry = {
          "request_index" => request_index,
          "kind" => "consolidation",
          "group_count" => group_count,
          "groups" => provisional_groups
        }

        request_groups_for_consolidation!(
          provisional_groups: provisional_groups,
          expected_group_count: group_count,
          payload_entry: payload_entry
        )
      end

      def request_groups_for_consolidation!(provisional_groups:, expected_group_count:, payload_entry:)
        request_index = payload_entry.fetch("request_index")
        request_kind = payload_entry.fetch("kind")
        expected_group_ids = provisional_groups.map { |group| Integer(group.fetch("id")) }.sort
        attempts = []
        current_prompt = request_input_for_provisional_groups(provisional_groups, expected_group_count)

        1.upto(INVALID_RESPONSE_MAX_ATTEMPTS) do |attempt|
          touch_run_heartbeat!(
            "current_request" => request_index,
            "current_request_kind" => request_kind,
            "current_group_count" => expected_group_count,
            "current_request_attempt" => attempt
          )

          check_stop_requested!(requests_count: attempts.size)
          response = client.create!(input: current_prompt, text_format: consolidation_output_format)
          check_stop_requested!(requests_count: attempts.size + 1)
          response_dump = safe_response_dump(response)
          extracted_groups = extract_payload!(response)
          assignment_groups = normalize_consolidation_groups(
            extracted_groups,
            expected_group_ids: expected_group_ids,
            expected_group_count: expected_group_count
          )

          attempts << {
            "attempt" => attempt,
            "stage" => "initial",
            "response" => response_dump
          }

          groups = expand_consolidation_groups(assignment_groups, provisional_groups)
          return request_result_tuple(
            groups: groups,
            payload_entry: payload_entry,
            request_kind: request_kind,
            attempts: attempts
          )
        rescue Error => e
          attempts << {
            "attempt" => attempt,
            "stage" => "initial",
            "error" => e.message,
            "response" => response_dump
          }

          if attempt < INVALID_RESPONSE_MAX_ATTEMPTS
            logger.warn(
              "[LlmGenreGroupingImporter] run_id=#{run.id} retrying invalid consolidation " \
              "request=#{request_index} attempt=#{attempt} error=#{e.message}"
            )
            current_prompt = retry_prompt_for_invalid_response(
              base_prompt: request_input_for_provisional_groups(provisional_groups, expected_group_count),
              error_message: e.message
            )
            next
          end

          if extracted_groups.present?
            logger.warn(
              "[LlmGenreGroupingImporter] run_id=#{run.id} switching consolidation to repair mode " \
              "request=#{request_index} error=#{e.message}"
            )
            return repair_invalid_consolidation_groups!(
              payload_entry: payload_entry,
              request_kind: request_kind,
              invalid_groups: extracted_groups,
              provisional_groups: provisional_groups,
              expected_group_ids: expected_group_ids,
              expected_group_count: expected_group_count,
              attempts: attempts,
              error_message: e.message
            )
          end

          raise
        end
      end

      def request_groups_for_prompt!(prompt:, expected_genres:, expected_group_count:, payload_entry:)
        request_index = payload_entry.fetch("request_index")
        request_kind = payload_entry.fetch("kind")
        attempts = []
        current_prompt = prompt

        1.upto(INVALID_RESPONSE_MAX_ATTEMPTS) do |attempt|
          touch_run_heartbeat!(
            "current_request" => request_index,
            "current_request_kind" => request_kind,
            "current_group_count" => expected_group_count,
            "current_request_attempt" => attempt
          )

          check_stop_requested!(requests_count: attempts.size)
          response = client.create!(input: current_prompt, text_format: output_format)
          check_stop_requested!(requests_count: attempts.size + 1)
          response_dump = safe_response_dump(response)
          extracted_groups = extract_payload!(response)
          groups = normalize_payload_groups(
            extracted_groups,
            expected_genres: expected_genres,
            expected_group_count: expected_group_count
          )

          attempts << {
            "attempt" => attempt,
            "stage" => "initial",
            "response" => response_dump
          }

          return request_result_tuple(
            groups: groups,
            payload_entry: payload_entry,
            request_kind: request_kind,
            attempts: attempts
          )
        rescue Error => e
          attempts << {
            "attempt" => attempt,
            "stage" => "initial",
            "error" => e.message,
            "response" => response_dump
          }

          if attempt < INVALID_RESPONSE_MAX_ATTEMPTS
            logger.warn(
              "[LlmGenreGroupingImporter] run_id=#{run.id} retrying invalid response " \
              "request=#{request_index} kind=#{request_kind} attempt=#{attempt} error=#{e.message}"
            )
            current_prompt = retry_prompt_for_invalid_response(base_prompt: prompt, error_message: e.message)
            next
          end

          if extracted_groups.present?
            logger.warn(
              "[LlmGenreGroupingImporter] run_id=#{run.id} switching to repair mode " \
              "request=#{request_index} kind=#{request_kind} error=#{e.message}"
            )
            begin
              return repair_invalid_groups!(
                payload_entry: payload_entry,
                request_kind: request_kind,
                invalid_groups: extracted_groups,
                expected_genres: expected_genres,
                expected_group_count: expected_group_count,
                attempts: attempts,
                error_message: e.message
              )
            rescue Error => repair_error
              if request_kind == "chunk"
                logger.warn(
                  "[LlmGenreGroupingImporter] run_id=#{run.id} using heuristic chunk repair " \
                  "request=#{request_index} error=#{repair_error.message}"
                )
                groups = heuristic_repair_chunk_groups(
                  raw_groups: extracted_groups,
                  expected_genres: expected_genres,
                  expected_group_count: expected_group_count
                )
                attempts << {
                  "attempt" => attempts.size + 1,
                  "stage" => "heuristic_repair",
                  "error" => repair_error.message
                }
                return request_result_tuple(
                  groups: groups,
                  payload_entry: payload_entry,
                  request_kind: request_kind,
                  attempts: attempts
                )
              end

              raise
            end
          end

          raise
        end
      end

      def repair_invalid_groups!(payload_entry:, request_kind:, invalid_groups:, expected_genres:, expected_group_count:, attempts:, error_message:)
        current_invalid_groups = invalid_groups
        current_error_message = error_message

        1.upto(REPAIR_INVALID_RESPONSE_MAX_ATTEMPTS) do |_repair_attempt|
          attempt_number = attempts.size + 1
          repair_prompt = repair_prompt_for_invalid_groups(
            invalid_groups: current_invalid_groups,
            expected_genres: expected_genres,
            expected_group_count: expected_group_count,
            error_message: current_error_message
          )
          touch_run_heartbeat!(
            "current_request" => payload_entry.fetch("request_index"),
            "current_request_kind" => request_kind,
            "current_group_count" => expected_group_count,
            "current_request_attempt" => attempt_number
          )

          check_stop_requested!(requests_count: attempts.count { |entry| entry.fetch("stage", "initial") != "heuristic_repair" })
          response = client.create!(input: repair_prompt, text_format: output_format)
          check_stop_requested!(requests_count: attempts.count { |entry| entry.fetch("stage", "initial") != "heuristic_repair" } + 1)
          response_dump = safe_response_dump(response)
          extracted_groups = extract_payload!(response)
          groups = normalize_payload_groups(
            extracted_groups,
            expected_genres: expected_genres,
            expected_group_count: expected_group_count
          )

          attempts << {
            "attempt" => attempt_number,
            "stage" => "repair",
            "response" => response_dump
          }

          return request_result_tuple(
            groups: groups,
            payload_entry: payload_entry,
            request_kind: request_kind,
            attempts: attempts
          )
        rescue Error => e
          attempts << {
            "attempt" => attempt_number,
            "stage" => "repair",
            "error" => e.message,
            "response" => response_dump
          }
          current_invalid_groups = extracted_groups if extracted_groups.present?
          current_error_message = e.message
        end

        raise Error, current_error_message
      end

      def request_result_tuple(groups:, payload_entry:, request_kind:, attempts:)
        attempt_count = attempts.count { |entry| entry.fetch("stage", "initial") != "heuristic_repair" }

        [
          groups,
          payload_entry.merge(
            "attempt_count" => attempt_count,
            "attempts" => attempts.map { |entry| entry.slice("attempt", "stage", "error") }
          ),
          {
            "request_index" => payload_entry.fetch("request_index"),
            "kind" => request_kind,
            "attempt_count" => attempt_count,
            "attempts" => attempts
          },
          attempt_count
        ]
      end

      def request_input_for_genres(genres, group_count)
        AppSetting.llm_genre_grouping_prompt_template
          .gsub(AppSetting::LLM_GENRE_GROUPING_INPUT_PLACEHOLDER, JSON.pretty_generate(genres))
          .gsub(AppSetting::LLM_GENRE_GROUPING_GROUP_COUNT_PLACEHOLDER, group_count.to_s)
      end

      def request_input_for_provisional_groups(provisional_groups, group_count)
        <<~TEXT.strip
          Fasse die vorläufigen Genre-Gruppen aus `Input` in genau #{group_count} endgültige Obergruppen zusammen.

          Gib das Ergebnis ausschließlich als JSON im Format von `Output` zurück.

          ABSOLUTE PFLICHTREGELN:
          1. Jede `id` aus den vorläufigen Gruppen darf genau ein einziges Mal in der gesamten Antwort vorkommen.
          2. Eine `id` darf niemals in zwei oder mehr Gruppen auftauchen.
          3. Keine `id` darf fehlen. Null fehlende IDs ist eine harte Pflicht.
          4. Erfinde keine zusätzlichen IDs.
          5. Gib keine Rohgenres zurück, sondern nur `provisional_group_ids`.
          6. Bevor du antwortest, führe intern einen vollständigen Abgleich zwischen allen Input-IDs und allen ausgegebenen IDs durch.
          7. Wenn auch nur eine einzige `id` fehlen oder doppelt vorkommen würde, musst du deine Antwort vor der Ausgabe korrigieren.

          Weitere Regeln:
          1. Fasse ähnliche oder fachlich nahe Gruppen sinnvoll zusammen.
          2. Jede Obergruppe braucht einen kurzen, redaktionell brauchbaren Namen auf Deutsch.
          3. `position` muss fortlaufend bei 1 beginnen und ohne Lücken bis zur letzten Gruppe reichen.
          4. Prüfe unmittelbar vor der Ausgabe deine Antwort selbst noch einmal und stelle sicher, dass jede einzelne Input-`id` exakt einmal vorkommt.

          Output:
          {
            "groups": [
              {
                "position": 1,
                "name": "Beispielgruppe",
                "provisional_group_ids": [ 1, 2 ]
              }
            ]
          }

          Input:
          #{JSON.pretty_generate(provisional_groups)}
        TEXT
      end

      def retry_prompt_for_invalid_response(base_prompt:, error_message:)
        <<~TEXT.strip
          #{base_prompt}

          Der letzte Versuch war ungültig und muss vollständig neu erstellt werden.

          Fehler im letzten Versuch:
          #{truncated_retry_error_message(error_message)}

          Zusätzliche Pflichtregeln:
          1. Jedes Input-Genre muss exakt einmal vorkommen.
          2. Kein Genre darf in mehr als einer Gruppe auftauchen.
          3. Kein Genre darf fehlen. Auch ein einziges fehlendes Genre macht die Antwort unzulässig.
          4. Halte die geforderte Gruppenanzahl exakt ein.
          5. Antworte nur mit vollständigem JSON im geforderten Format.
          6. Prüfe deine Antwort vor der Ausgabe selbst auf doppelte oder fehlende Genres.
          7. Insbesondere bei Grenzfällen musst du das Genre trotzdem genau einer Gruppe zuordnen. Weglassen ist verboten.
        TEXT
      end

      def repair_prompt_for_invalid_groups(invalid_groups:, expected_genres:, expected_group_count:, error_message:)
        <<~TEXT.strip
          Korrigiere die fehlerhafte Genre-Gruppierung aus `InvalidOutput`.

          Ziel:
          - genau #{expected_group_count} Obergruppen
          - `position` fortlaufend von 1 bis #{expected_group_count}
          - jedes Genre aus `ExpectedGenres` genau einmal
          - kein Genre darf mehrfach vorkommen
          - kein Genre aus `ExpectedGenres` darf fehlen
          - keine zusätzlichen Genres
          - keine leeren Gruppen
          - kurze, redaktionell brauchbare Gruppennamen auf Deutsch

          Der letzte Fehler war:
          #{truncated_retry_error_message(error_message)}

          Prüfe vor der Ausgabe jedes Genre aus `ExpectedGenres` einzeln gegen deine Antwort.

          Gib ausschließlich vollständiges JSON im Format von `Output` zurück.

          Output:
          {
            "groups": [
              {
                "position": 1,
                "name": "Beispielgruppe",
                "genres": [ "Genre A", "Genre B" ]
              }
            ]
          }

          ExpectedGenres:
          #{JSON.pretty_generate(expected_genres)}

          InvalidOutput:
          #{JSON.pretty_generate({ groups: invalid_groups })}
        TEXT
      end

      def repair_prompt_for_invalid_consolidation_groups(invalid_groups:, provisional_groups:, expected_group_count:, error_message:)
        <<~TEXT.strip
          Korrigiere die fehlerhafte Konsolidierung aus `InvalidOutput`.

          Ziel:
          - genau #{expected_group_count} Obergruppen
          - `position` fortlaufend von 1 bis #{expected_group_count}
          - jede `id` aus `ProvisionalGroups` genau einmal
          - keine `id` darf mehrfach vorkommen
          - keine `id` aus `ProvisionalGroups` darf fehlen
          - keine zusätzlichen IDs
          - keine leeren Gruppen
          - kurze, redaktionell brauchbare Gruppennamen auf Deutsch
          - gib nur `provisional_group_ids` zurück, keine Rohgenres

          Der letzte Fehler war:
          #{truncated_retry_error_message(error_message)}

          Prüfe vor der Ausgabe jede `id` aus `ProvisionalGroups` einzeln gegen deine Antwort.

          Gib ausschließlich vollständiges JSON im Format von `Output` zurück.

          Output:
          {
            "groups": [
              {
                "position": 1,
                "name": "Beispielgruppe",
                "provisional_group_ids": [ 1, 2 ]
              }
            ]
          }

          ProvisionalGroups:
          #{JSON.pretty_generate(provisional_groups)}

          InvalidOutput:
          #{JSON.pretty_generate({ groups: invalid_groups })}
        TEXT
      end

      def truncated_retry_error_message(error_message)
        message = error_message.to_s.strip
        return message if message.length <= INVALID_RESPONSE_ERROR_MESSAGE_LIMIT

        "#{message.first(INVALID_RESPONSE_ERROR_MESSAGE_LIMIT - 3)}..."
      end

      def output_format
        {
          type: "json_schema",
          name: OUTPUT_SCHEMA_NAME,
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            required: [ OUTPUT_GROUPS_KEY ],
            properties: {
              OUTPUT_GROUPS_KEY => {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: %w[position name genres],
                  properties: {
                    position: { type: "integer" },
                    name: { type: "string" },
                    genres: {
                      type: "array",
                      items: { type: "string" }
                    }
                  }
                }
              }
            }
          }
        }
      end

      def consolidation_output_format
        {
          type: "json_schema",
          name: CONSOLIDATION_OUTPUT_SCHEMA_NAME,
          strict: true,
          schema: {
            type: "object",
            additionalProperties: false,
            required: [ OUTPUT_GROUPS_KEY ],
            properties: {
              OUTPUT_GROUPS_KEY => {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: %w[position name provisional_group_ids],
                  properties: {
                    position: { type: "integer" },
                    name: { type: "string" },
                    provisional_group_ids: {
                      type: "array",
                      items: { type: "integer" }
                    }
                  }
                }
              }
            }
          }
        }
      end

      def extract_payload!(response)
        parsed_payload = extract_parsed_payload(response)
        return extract_groups_from_payload(parsed_payload) if parsed_payload.present?

        output_text = extract_output_text(response)
        raise Error, "OpenAI-Antwort enthält keinen JSON-Text." if output_text.blank?

        payload = JSON.parse(output_text)
        extract_groups_from_payload(payload)
      rescue JSON::ParserError => e
        logger.error("[LlmGenreGroupingImporter] run_id=#{run.id} invalid json response=#{safe_response_dump(response)}")
        raise Error, "OpenAI-Antwort enthält ungültiges JSON: #{e.message}"
      end

      def extract_groups_from_payload(payload)
        raise Error, "OpenAI-Antwort ist kein JSON-Objekt." unless payload.is_a?(Hash)

        groups = payload[OUTPUT_GROUPS_KEY]
        raise Error, "OpenAI-Antwort enthält kein #{OUTPUT_GROUPS_KEY}-Array." unless groups.is_a?(Array)

        groups
      end

      def extract_parsed_payload(response)
        return extract_parsed_payload_from_object(response) if response.respond_to?(:output)

        extract_parsed_payload_from_hash(response)
      end

      def extract_parsed_payload_from_object(response)
        Array(response.output).each do |item|
          next unless item.respond_to?(:content)

          Array(item.content).each do |content|
            next unless content.respond_to?(:type) && content.type.to_sym == :output_text

            parsed = content.respond_to?(:parsed) ? content.parsed : nil
            next if parsed.blank?

            return parsed.respond_to?(:to_h) ? parsed.to_h : parsed
          end
        end

        nil
      end

      def extract_parsed_payload_from_hash(response)
        Array(response["output"]).each do |item|
          Array(item["content"]).each do |content|
            next unless content["type"].to_s == "output_text"

            parsed = content["parsed"] || content[:parsed]
            return parsed if parsed.present?
          end
        end

        nil
      end

      def extract_output_text(response)
        return response.output_text.to_s if response.respond_to?(:output_text)

        response["output_text"].to_s.presence || extract_output_text_from_hash_content(response)
      end

      def extract_output_text_from_hash_content(response)
        Array(response["output"]).flat_map { |item| Array(item["content"]) }
          .find { |content| content["type"] == "output_text" }
          &.fetch("text", "")
          .to_s
      end

      def normalize_payload_groups(groups, expected_genres:, expected_group_count:)
        normalized_groups = Array(groups).map { |group| normalize_payload_group(group) }.sort_by { |group| group.fetch(:position) }
        if normalized_groups.size != expected_group_count
          raise Error, "OpenAI-Antwort enthält #{normalized_groups.size} Gruppen, erwartet werden #{expected_group_count}."
        end

        expected_positions = (1..expected_group_count).to_a
        positions = normalized_groups.map { |group| group.fetch(:position) }
        raise Error, "OpenAI-Antwort enthält ungültige Positionen." unless positions == expected_positions

        normalized_groups.each do |group|
          raise Error, "OpenAI-Antwort enthält eine Gruppe ohne Namen." if group.fetch(:name).blank?
          raise Error, "OpenAI-Antwort enthält eine leere Gruppe." if group.fetch(:genres).empty?
        end

        assigned_genres = normalized_groups.flat_map { |group| group.fetch(:genres) }
        expected_genres = expected_genres.sort
        unknown_genres = assigned_genres.uniq.sort - expected_genres
        missing_genres = expected_genres - assigned_genres.uniq.sort
        raise Error, "OpenAI-Antwort enthält unbekannte Genres: #{unknown_genres.join(", ")}" if unknown_genres.any?
        raise Error, "OpenAI-Antwort enthält nicht alle Genres: #{missing_genres.join(", ")}" if missing_genres.any?

        slugs = normalized_groups.map do |group|
          group.fetch(:name).to_s.parameterize.presence || "group-#{group.fetch(:position)}"
        end
        duplicate_slugs = slugs.group_by(&:itself).select { |_, values| values.size > 1 }.keys
        raise Error, "OpenAI-Antwort enthält doppelte Gruppennamen." if duplicate_slugs.any?

        normalized_groups
      end

      def normalize_consolidation_groups(groups, expected_group_ids:, expected_group_count:)
        normalized_groups = Array(groups).map { |group| normalize_consolidation_group(group) }.sort_by { |group| group.fetch(:position) }
        if normalized_groups.size != expected_group_count
          raise Error, "OpenAI-Antwort enthält #{normalized_groups.size} Gruppen, erwartet werden #{expected_group_count}."
        end

        expected_positions = (1..expected_group_count).to_a
        positions = normalized_groups.map { |group| group.fetch(:position) }
        raise Error, "OpenAI-Antwort enthält ungültige Positionen." unless positions == expected_positions

        normalized_groups.each do |group|
          raise Error, "OpenAI-Antwort enthält eine Gruppe ohne Namen." if group.fetch(:name).blank?
          raise Error, "OpenAI-Antwort enthält eine leere Gruppe." if group.fetch(:provisional_group_ids).empty?
        end

        assigned_ids = normalized_groups.flat_map { |group| group.fetch(:provisional_group_ids) }
        unknown_ids = assigned_ids.uniq.sort - expected_group_ids
        missing_ids = expected_group_ids - assigned_ids.uniq.sort
        raise Error, "OpenAI-Antwort enthält unbekannte Gruppen-IDs: #{unknown_ids.join(", ")}" if unknown_ids.any?
        raise Error, "OpenAI-Antwort enthält nicht alle Gruppen-IDs: #{missing_ids.join(", ")}" if missing_ids.any?

        slugs = normalized_groups.map do |group|
          group.fetch(:name).to_s.parameterize.presence || "group-#{group.fetch(:position)}"
        end
        duplicate_slugs = slugs.group_by(&:itself).select { |_, values| values.size > 1 }.keys
        raise Error, "OpenAI-Antwort enthält doppelte Gruppennamen." if duplicate_slugs.any?

        normalized_groups
      end

      def normalize_payload_group(group)
        raise Error, "OpenAI-Antwort enthält einen ungültigen Gruppeneintrag." unless group.is_a?(Hash)

        {
          position: Integer(group["position"] || group[:position], exception: false),
          name: (group["name"] || group[:name]).to_s.strip,
          genres: normalize_distinct_genres(Array(group["genres"] || group[:genres]).map(&:to_s))
        }.tap do |normalized_group|
          raise Error, "OpenAI-Antwort enthält keine gültige Gruppenposition." if normalized_group[:position].blank?
        end
      end

      def normalize_consolidation_group(group)
        raise Error, "OpenAI-Antwort enthält einen ungültigen Gruppeneintrag." unless group.is_a?(Hash)

        {
          position: Integer(group["position"] || group[:position], exception: false),
          name: (group["name"] || group[:name]).to_s.strip,
          provisional_group_ids: Array(group["provisional_group_ids"] || group[:provisional_group_ids]).filter_map do |value|
            Integer(value, exception: false)
          end.uniq.sort
        }.tap do |normalized_group|
          raise Error, "OpenAI-Antwort enthält keine gültige Gruppenposition." if normalized_group[:position].blank?
        end
      end

      def expand_consolidation_groups(assignment_groups, provisional_groups)
        provisional_groups_by_id = provisional_groups.index_by { |group| Integer(group.fetch("id")) }

        assignment_groups.map do |group|
          {
            position: group.fetch(:position),
            name: group.fetch(:name),
            genres: group.fetch(:provisional_group_ids).flat_map { |id| Array(provisional_groups_by_id.fetch(id).fetch("genres")) }.uniq.sort
          }
        end
      end

      def heuristic_repair_chunk_groups(raw_groups:, expected_genres:, expected_group_count:)
        expected_genres = expected_genres.sort
        expected_genre_lookup = expected_genres.index_with(true)
        normalized_groups = Array(raw_groups).map { |group| normalize_payload_group(group) }.sort_by { |group| group.fetch(:position) }
        raise Error, "OpenAI-Antwort enthält keine verwertbaren Gruppen." if normalized_groups.empty?

        groups = normalized_groups.first(expected_group_count).each_with_index.map do |group, index|
          {
            position: index + 1,
            name: group.fetch(:name).presence || "Gruppe #{index + 1}",
            genres: group.fetch(:genres).dup
          }
        end

        while groups.size < expected_group_count
          position = groups.size + 1
          groups << {
            position: position,
            name: "Gruppe #{position}",
            genres: []
          }
        end

        assigned_lookup = {}
        groups.each do |group|
          group[:genres] = group.fetch(:genres).each_with_object([]) do |genre, deduplicated|
            next unless expected_genre_lookup[genre]
            next if assigned_lookup[genre]

            deduplicated << genre
            assigned_lookup[genre] = true
          end
        end

        missing_genres = expected_genres.reject { |genre| assigned_lookup[genre] }

        groups.each do |group|
          next unless group[:genres].empty?
          next if missing_genres.empty?

          group[:genres] << missing_genres.shift
        end

        until missing_genres.empty?
          target_group = groups.min_by { |group| [ group[:genres].size, group[:position] ] }
          target_group[:genres] << missing_genres.shift
        end

        groups.each do |group|
          next if group[:genres].any?

          donor_group = groups.select { |candidate| candidate[:genres].size > 1 }
            .max_by { |candidate| [ candidate[:genres].size, -candidate[:position] ] }
          raise Error, "Heuristische Chunk-Reparatur konnte keine leeren Gruppen auffüllen." if donor_group.blank?

          group[:genres] << donor_group[:genres].pop
        end

        groups.each do |group|
          group[:genres] = group.fetch(:genres).uniq.sort
        end

        validate_heuristic_chunk_groups!(groups, expected_genres: expected_genres, expected_group_count: expected_group_count)
        groups
      end

      def validate_heuristic_chunk_groups!(groups, expected_genres:, expected_group_count:)
        positions = groups.map { |group| group.fetch(:position) }
        raise Error, "Heuristische Chunk-Reparatur erzeugte ungültige Positionen." unless positions == (1..expected_group_count).to_a

        assigned_genres = groups.flat_map { |group| group.fetch(:genres) }
        missing_genres = expected_genres - assigned_genres
        raise Error, "Heuristische Chunk-Reparatur verlor Genres: #{missing_genres.join(", ")}" if missing_genres.any?

        raise Error, "Heuristische Chunk-Reparatur erzeugte leere Gruppen." if groups.any? { |group| group.fetch(:genres).empty? }
      end

      def repair_invalid_consolidation_groups!(
        payload_entry:,
        request_kind:,
        invalid_groups:,
        provisional_groups:,
        expected_group_ids:,
        expected_group_count:,
        attempts:,
        error_message:
      )
        current_invalid_groups = invalid_groups
        current_error_message = error_message

        1.upto(REPAIR_INVALID_RESPONSE_MAX_ATTEMPTS) do |_repair_attempt|
          attempt_number = attempts.size + 1
          repair_prompt = repair_prompt_for_invalid_consolidation_groups(
            invalid_groups: current_invalid_groups,
            provisional_groups: provisional_groups,
            expected_group_count: expected_group_count,
            error_message: current_error_message
          )
          touch_run_heartbeat!(
            "current_request" => payload_entry.fetch("request_index"),
            "current_request_kind" => request_kind,
            "current_group_count" => expected_group_count,
            "current_request_attempt" => attempt_number
          )

          check_stop_requested!(requests_count: attempts.count { |entry| entry.fetch("stage", "initial") != "heuristic_repair" })
          response = client.create!(input: repair_prompt, text_format: consolidation_output_format)
          check_stop_requested!(requests_count: attempts.count { |entry| entry.fetch("stage", "initial") != "heuristic_repair" } + 1)
          response_dump = safe_response_dump(response)
          extracted_groups = extract_payload!(response)
          assignment_groups = normalize_consolidation_groups(
            extracted_groups,
            expected_group_ids: expected_group_ids,
            expected_group_count: expected_group_count
          )

          attempts << {
            "attempt" => attempt_number,
            "stage" => "repair",
            "response" => response_dump
          }

          groups = expand_consolidation_groups(assignment_groups, provisional_groups)
          return request_result_tuple(
            groups: groups,
            payload_entry: payload_entry,
            request_kind: request_kind,
            attempts: attempts
          )
        rescue Error => e
          attempts << {
            "attempt" => attempt_number,
            "stage" => "repair",
            "error" => e.message,
            "response" => response_dump
          }
          current_invalid_groups = extracted_groups if extracted_groups.present?
          current_error_message = e.message
        end

        raise Error, current_error_message
      end

      def persist_snapshot!(groups:, request_payload:, raw_response:, selected_count:, requested_group_count:, effective_group_count:)
        snapshot_model.transaction do
          snapshot = snapshot_model.create!(
            import_run: run,
            snapshot_key: SecureRandom.uuid,
            active: false,
            requested_group_count: requested_group_count,
            effective_group_count: effective_group_count,
            source_genres_count: selected_count,
            model: client_model,
            prompt_template_digest: Digest::SHA256.hexdigest(AppSetting.llm_genre_grouping_prompt_template),
            request_payload: request_payload,
            raw_response: raw_response
          )

          groups.each do |group|
            snapshot.groups.create!(
              position: group.fetch(:position),
              name: group.fetch(:name),
              member_genres: group.fetch(:genres)
            )
          end

          snapshot
        end
      end

      def safe_response_dump(response)
        dumped =
          if response.respond_to?(:deep_to_h)
            response.deep_to_h
          elsif response.respond_to?(:to_h)
            response.to_h
          else
            response
          end

        dumped.is_a?(Hash) ? dumped.deep_stringify_keys : dumped
      end

      def context_limit_error?(error)
        error.message.to_s.match?(CONTEXT_LIMIT_ERROR_PATTERN)
      end

      def touch_run_heartbeat!(extra_metadata = {})
        return unless run_running?

        metadata = current_run_metadata.merge(extra_metadata.deep_stringify_keys)
        run.update_columns(metadata: metadata, updated_at: Time.current)
        Backend::ImportRunsBroadcaster.broadcast!
      end

      def update_run_progress!(selected_count:, skipped_count:, groups_count:, requests_count:, requested_group_count:, effective_group_count:, source_genres_count:, **extra_metadata)
        return unless run_running?

        run.update!(
          fetched_count: selected_count,
          filtered_count: skipped_count,
          imported_count: groups_count,
          upserted_count: requests_count,
          metadata: current_run_metadata.merge(
            {
              "genres_selected_count" => selected_count,
              "genres_skipped_count" => skipped_count,
              "groups_created_count" => groups_count,
              "requests_count" => requests_count,
              "requested_group_count" => requested_group_count,
              "effective_group_count" => effective_group_count,
              "source_genres_count" => source_genres_count
            }
          ).merge(extra_metadata.deep_stringify_keys)
        )
        Backend::ImportRunsBroadcaster.broadcast!
      end

      def stop_requested?
        ActiveModel::Type::Boolean.new.cast(current_run_metadata["stop_requested"])
      end

      def check_stop_requested!(requests_count:)
        Importing::CooperativeStop.check!(-> { stop_requested? }, requests_count:)
      end

      def run_running?
        run.reload.status == "running"
      end

      def canceled_result(selected_count:, skipped_count:, requested_group_count:, effective_group_count:, requests_count: 0)
        Result.new(
          selected_count: selected_count,
          skipped_count: skipped_count,
          groups_count: 0,
          requests_count: requests_count,
          snapshot_id: nil,
          snapshot_key: nil,
          requested_group_count: requested_group_count,
          effective_group_count: effective_group_count,
          model: client_model,
          canceled: true
        )
      end

      def normalized_metadata(metadata)
        metadata.is_a?(Hash) ? metadata.deep_stringify_keys : {}
      end

      def current_run_metadata
        normalized_metadata(run.reload.metadata)
      end

      def client_model
        client.model
      end
    end
  end
end
