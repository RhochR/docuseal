# frozen_string_literal: true

module Submitters
  # Server side counterpart of app/javascript/submission_form/calculator.js. Formula fields are computed
  # in the signing form for display, and again here when the form is submitted, so the stored value
  # (result PDF, API, webhooks) does not depend on the browser.
  module FormulaCalculator
    MAX_DEPTH = 10
    EPOCH = Date.new(1970, 1, 1)
    NUMERIC_REGEXP = /\A\s*-?(?:\d+\.?\d*|\.\d+)\s*\z/
    TODAY_TOKEN = 'today()'
    NULL_TOKEN = 'null'

    module_function

    def calculate(formula, values, submission)
      normalize_number(evaluate(formula, values, submission))
    end

    def calculate_date(formula, values, submission)
      days = evaluate(formula, values, submission)

      return unless days.is_a?(Numeric) && days.to_f.finite?

      (EPOCH + days.floor).iso8601
    end

    def eval_text(formula, values, submission, depth = 0)
      return '' if depth > MAX_DEPTH

      formula.gsub(/{{(.*?)}}/) do
        uuid = Regexp.last_match(1)
        field = submission.fields_uuid_index[uuid]
        nested_formula = field&.dig('preferences', 'formula').presence

        if nested_formula && field['type'] == 'text'
          eval_text(nested_formula, values, submission, depth + 1)
        elsif nested_formula
          calculate_nested(nested_formula, field, values, submission).to_s
        else
          Array.wrap(values[uuid]).join(', ')
        end
      end
    end

    def calculate_nested(formula, field, values, submission)
      normalized_formula = Submitters::SubmitValues.normalize_formula(formula, submission, submission_values: values)

      if field['type'] == 'date'
        calculate_date(normalized_formula, values, submission)
      else
        calculate(normalized_formula, values, submission)
      end
    end

    def evaluate(formula, values, submission)
      expression = formula.gsub(/{{(.*?)}}/) do
        uuid = Regexp.last_match(1)

        if submission.fields_uuid_index.dig(uuid, 'type') == 'date'
          date_token(values[uuid])
        else
          numeric_token(values[uuid])
        end
      end

      build_calculator(submission.account.timezone).evaluate(expression.downcase)
    rescue Dentaku::Error, ZeroDivisionError, FloatDomainError, Math::DomainError, TypeError
      nil
    end

    # Only numbers are ever substituted into the expression, so a submitted value can not change its structure.
    def numeric_token(value)
      value = value.first if value.is_a?(Array)

      return '0.0' unless value.to_s.match?(NUMERIC_REGEXP)

      "(#{BigDecimal(value.to_s.strip).to_s('F')})"
    end

    def date_token(value)
      return NULL_TOKEN if value.blank?
      return TODAY_TOKEN if value == '{{date}}'

      "(#{(Date.iso8601(value.to_s[0, 10]) - EPOCH).to_i})"
    rescue Date::Error
      NULL_TOKEN
    end

    def normalize_number(number)
      return unless number.is_a?(Numeric)

      float = number.to_f

      return unless float.finite?

      (float % 1).zero? ? float.to_i : float
    end

    # rubocop:disable Metrics
    def build_calculator(timezone)
      calculator = Dentaku::Calculator.new

      # Same rounding as Math.round in the browser: halves go towards positive infinity.
      calculator.add_function(:round, :numeric, lambda { |number, precision = 0|
        factor = 10.0**precision.to_i

        ((number.to_f * factor) + 0.5).floor / factor
      })
      calculator.add_function(:roundup, :numeric, lambda { |number, precision = 0|
        factor = 10.0**precision.to_i
        scaled = number.to_f * factor

        (scaled.negative? ? -(-scaled).floor : scaled.ceil) / factor
      })
      calculator.add_function(:rounddown, :numeric, lambda { |number, precision = 0|
        factor = 10.0**precision.to_i
        scaled = number.to_f * factor

        (scaled.negative? ? -(-scaled).ceil : scaled.floor) / factor
      })

      calculator.add_function(:floor, :numeric, ->(number) { number.to_f.floor })
      calculator.add_function(:ceil, :numeric, ->(number) { number.to_f.ceil })
      calculator.add_function(:pow, :numeric, ->(base, exponent) { base.to_f**exponent.to_f })
      calculator.add_function(:pi, :numeric, -> { Math::PI })
      calculator.add_function(:e, :numeric, -> { Math::E })

      calculator.add_function(:length, :numeric, ->(value) { value.to_s.length })
      calculator.add_function(:upcase, :string, ->(value) { value.to_s.upcase })
      calculator.add_function(:downcase, :string, ->(value) { value.to_s.downcase })
      calculator.add_function(:trim, :string, ->(value) { value.to_s.strip })

      calculator.add_function(:today, :numeric, -> { (Time.current.in_time_zone(timezone).to_date - EPOCH).to_i })
      calculator.add_function(:datedif, :numeric, ->(from, to, unit) { date_diff(from, to, unit) })

      calculator
    end
    # rubocop:enable Metrics

    def date_diff(from, to, unit)
      return if from.nil? || to.nil?

      from = from.to_i
      to = to.to_i
      unit = unit.to_s.downcase

      return to - from if unit == 'd'

      first, last = [from, to].minmax
      first_date = EPOCH + first
      last_date = EPOCH + last

      months = ((last_date.year - first_date.year) * 12) + last_date.month - first_date.month
      months -= 1 if last_date.day < first_date.day
      sign = to < from ? -1 : 1

      case unit
      when 'm' then sign * months
      when 'y' then sign * (months / 12)
      end
    end
  end
end
