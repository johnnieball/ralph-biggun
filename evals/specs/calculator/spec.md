# Calculator Library

Build a simple calculator library in TypeScript (Bun runtime, Vitest tests).

## What it does

A calculator module that can:

- Add two numbers
- Subtract two numbers
- Multiply two numbers
- Divide two numbers (with proper division-by-zero handling)
- Evaluate a string expression like "2 + 3" and return the numeric result

## Details

The four basic operations should be individual exported functions: add, subtract, multiply, divide.

Division by zero should throw an error with a message that includes "division by zero".

The string evaluator (evaluate function) should accept expressions like:

- "2 + 3" → 5
- "10 - 4" → 6
- "3 \* 7" → 21
- "8 / 2" → 4
- "5 / 0" → throws division by zero
- "abc" → throws error for invalid input

Keep it simple — no operator precedence, no parentheses, just "number operator number" format.

All functions should handle positive, negative, and zero values correctly.
