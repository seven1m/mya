# Amazon Q Developer Rules for Mya Compiler Project

## Project Overview
This is a Ruby-based compiler project called "Mya" that compiles a statically-typed subset of Ruby to LLVM IR. The project is experimental and focuses on type systems, type inference, and compiler construction.

## Architecture
- **Compiler**: Main compilation pipeline using Prism parser
- **TypeChecker**: Constraint solver
- **VM**: Virtual machine for executing compiled code
- **Instructions**: Intermediate representation for compiled code
- **Backends**: Code generation (currently LLVM)

## Code Style and Standards

### Ruby Style
- Use **SyntaxTree** formatter with 120 character line width
- Single quotes preferred over double quotes
- Trailing commas enabled in collections
- No auto-ternary operators
- 2-space indentation for Ruby files
- 4-space indentation for C/C++ files

### Type System Conventions
- Use Ruby terminology: "methods" not "functions"
- Type representations: `([(param_types)] -> return_type)`
- Concrete types: simple names (int, str, bool, nil)
- Object types: `(object ClassName)`
- Method types: `([(receiver, params)] -> return_type)`

### Testing
- Use Minitest with spec-style syntax
- Custom `must_equal_with_diff` matcher for complex comparisons
- Test files end with `_spec.rb`
- Use descriptive test names: `'compiles method definitions'`
- Group related tests in describe blocks

### Comments
- Avoid comments that just explain what code does
- Use comments for complex algorithms or non-obvious decisions
- Document public APIs and class purposes
- Prefer self-documenting code over comments

### File Organization
- `lib/mya/` - Main library code
- `lib/mya/compiler/` - Compiler components
- `spec/` - Test files
- `examples/` - Example Mya programs
- `src/` - C code for runtime

### Dependencies
- **Prism**: Ruby parser
- **ruby-llvm**: LLVM bindings
- **Minitest**: Testing framework
- **SyntaxTree**: Code formatting

### Development Workflow
- Use `bundle exec rake spec` to run tests
- Use `bundle exec rake lint` for style checking
- Use `bundle exec rake watch` for continuous testing
- Docker support available for consistent environments
