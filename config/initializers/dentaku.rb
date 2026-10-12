# frozen_string_literal: true

# Formulas are evaluated on the server with values that signers submit. Dentaku computes ^ and << with arbitrary
# precision integers and decimals, so a small input such as 9 ^ 999999999 keeps a thread busy for ever. Calculate powers
# with floats (like the calculator in the browser) and limit bit shifts.
module DentakuSafeArithmetic
  MAX_SHIFT = 64

  module Exponentiation
    private

    def calculate(left_value, right_value)
      result = cast(left_value).to_f**cast(right_value).to_f

      unless result.is_a?(Float) && result.finite?
        raise Dentaku::ArgumentError.for(:invalid_value, actual: right_value), 'Result of ^ is not a finite number'
      end

      result
    end
  end

  module ShiftLeft
    def value(context = {})
      amount = right.value(context)

      unless amount.is_a?(Integer) && amount.between?(0, MAX_SHIFT)
        raise Dentaku::ArgumentError.for(:invalid_value, actual: amount), "Shift must be between 0 and #{MAX_SHIFT}"
      end

      super
    end
  end
end

Dentaku::AST::Exponentiation.prepend(DentakuSafeArithmetic::Exponentiation)
Dentaku::AST::BitwiseShiftLeft.prepend(DentakuSafeArithmetic::ShiftLeft)
